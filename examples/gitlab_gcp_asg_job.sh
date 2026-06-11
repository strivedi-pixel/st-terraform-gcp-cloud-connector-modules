#!/bin/bash

deploy_type=gcp
# image and image_name come from CI environment variables.
# image=true  → use image_name as GCP image override
# image=false → skip image override, use default
image="${image:-false}"
image_name="${image_name:-}"
ec_job=ec_asg_job.py
asg_suite=true

log_this_and_run() {
    echo "[$(date +%Y-%d-%m-%H-%M-%S) -> $(basename $0)]:$(printf ' %s' "$@")"
    echo "----------------------------------"
    eval "$@"
    echo "----------------------------------"
}

cd_dir() {
    dir_path="$1"
    log_this_and_run "cd $dir_path"
}

pull_latest() {
    git stash
    git checkout master || :
    git pull
    git checkout $1
    git pull
}

clone_bamboo_build_smoke_test_scripts() {
    cd ${CI_PROJECT_DIR}/cloned_repo
    if [ -d "bamboo-build-smoke-test-scripts" ]; then
        echo "bamboo-build-smoke-test-scripts already cloned"
        cd_dir bamboo-build-smoke-test-scripts
        pull_latest
    else
        git clone -b master https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.corp.zscaler.com/zscaler/ztw/automation_stuff/bamboo-build-smoke-test-scripts.git || true
    fi
}

clone_zztest() {
    cd ${CI_PROJECT_DIR}/cloned_repo
    if [ -d "automation_repo" ]; then
        echo "automation_repo already cloned"
        cd_dir automation_repo
        pull_latest
    else
        git clone -b master https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.corp.zscaler.com/zscaler/ztw/automation_stuff/automation_repo.git || true
    fi
}

clone_workloads_sre() {
    cd ${CI_PROJECT_DIR}/cloned_repo
    if [ -d "workloads-sre" ]; then
        echo "workloads-sre already cloned"
        cd_dir workloads-sre
        pull_latest
    else
        git clone -b main https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.corp.zscaler.com/zscaler/ztw/automation_stuff/workloads-sre.git || true
    fi
}

clone_terraform_gcp_cloud_connector_modules() {
    cd ${CI_PROJECT_DIR}/cloned_repo
    if [ -d "terraform-gcp-cloud-connector-modules" ]; then
        echo "terraform-gcp-cloud-connector-modules already cloned"
        cd_dir terraform-gcp-cloud-connector-modules
        pull_latest
    else
        git clone -b main https://gitlab-ci-token:${CI_JOB_TOKEN}@github.com/zscaler/terraform-gcp-cloud-connector-modules.git || true
    fi
}

clone_bamboo_build_smoke_test_scripts
clone_workloads_sre
clone_zztest
clone_terraform_gcp_cloud_connector_modules

WORKLOAD_SRE_WORKSPACE=${CI_PROJECT_DIR}/cloned_repo/workloads-sre
ZZTEST_WORKSPACE=${CI_PROJECT_DIR}/cloned_repo/automation_repo
TERRAFORM_WORKSPACE=${CI_PROJECT_DIR}/cloned_repo/terraform-gcp-cloud-connector-modules
export PYTHONPATH=${CI_PROJECT_DIR}/cloned_repo/src/
BAMBOO_BUILD_SMOKE_TEST_SCRIPTS_WORKSPACE=${CI_PROJECT_DIR}/cloned_repo/bamboo-build-smoke-test-scripts

remove_all_last_logs_and_report_file() {
    echo ">>>> Cleaning up last run logs and reports."
    if [ -f "${CI_PROJECT_DIR}/cloned_repo/report.html" ]; then
        echo "Removing old html report from ${CI_PROJECT_DIR}/cloned_repo"
        rm -f "${CI_PROJECT_DIR}/cloned_repo/report.html"
    fi
    if [ -f "${CI_PROJECT_DIR}/cloned_repo/report.zip" ]; then
        echo "Removing old zip report from ${CI_PROJECT_DIR}/cloned_repo"
        rm -f "${CI_PROJECT_DIR}/cloned_repo/report.zip"
    fi
    if [ -f "${CI_PROJECT_DIR}/cloned_repo/test_summary_report.html" ]; then
        echo "Removing old html report from ${CI_PROJECT_DIR}/cloned_repo"
        rm -f "${CI_PROJECT_DIR}/cloned_repo/test_summary_report.html"
    fi
    if [ -f "${ZZTEST_WORKSPACE}/suites/smoke/regr-smoke-testbed.yml" ]; then
        echo "Removing stale testbed file from ${ZZTEST_WORKSPACE}"
        rm -f "${ZZTEST_WORKSPACE}/suites/smoke/regr-smoke-testbed.yml"
    fi
    if [ -f "${ZZTEST_WORKSPACE}/src/utils/ec/test_summary_report.html" ]; then
        echo "Removing old html report"
        rm -f "${ZZTEST_WORKSPACE}/src/utils/ec/test_summary_report.html"
    fi
    if [ -d "${ZZTEST_WORKSPACE}/suites/smoke/archive-dir" ]; then
        echo "Removing old archive-dir"
        rm -rf "${ZZTEST_WORKSPACE}/suites/smoke/archive-dir"
    fi
    for d in ${ZZTEST_WORKSPACE}/suites/smoke/*.html; do
        echo "Removing old report $d"
        rm -rf "$d"
    done
    if [ ! -z ${deploy_type} ] && [ "${deploy_type}" == "gcp" ]; then
        if [ -f "${ZZTEST_WORKSPACE}/suites/smoke/gcp_testbed.yml" ]; then
            echo "Removing stale testbed file"
            rm -f "${ZZTEST_WORKSPACE}/suites/smoke/gcp_testbed.yml"
        fi
    fi
}

copy_html_report_to_workspace() {
    if [ -f "${CI_PROJECT_DIR}/cloned_repo/report.html" ]; then
        echo "Removing old html report"
        rm -f "${CI_PROJECT_DIR}/cloned_repo/report.html"
    fi
    if [ -f "${CI_PROJECT_DIR}/cloned_repo/report.zip" ]; then
        echo "Removing old zip report from ${CI_PROJECT_DIR}/cloned_repo"
        rm -f "${CI_PROJECT_DIR}/cloned_repo/report.zip"
    fi
    if [ -f "${CI_PROJECT_DIR}/cloned_repo/test_summary_report.html" ]; then
        echo "Removing old test_summary_report html report"
        rm -f "${CI_PROJECT_DIR}/cloned_repo/test_summary_report.html"
    fi
    echo "Copying generated html report to workspace"
    cp -p "$(ls ${ZZTEST_WORKSPACE}/suites/smoke/*.html -tr1 | tail -1)" "${CI_PROJECT_DIR}/cloned_repo/report.html"
    cp -p "$(ls ${ZZTEST_WORKSPACE}/src/utils/ec/test_summary_report.html -tr1 | tail -1)" "${CI_PROJECT_DIR}/cloned_repo/test_summary_report.html"
    zip -9q ${CI_PROJECT_DIR}/cloned_repo/report "${CI_PROJECT_DIR}/cloned_repo/report.html"
}

echo "Cloud details: ${cloud}"
echo "Deploy type: ${deploy_type}"
echo "Use custom image?: ${image}"
if [ "${image}" = "true" ]; then
    echo "Image name: ${image_name}"
else
    echo "Image name: <not set — using default>"
fi

JOB_FILE="${ec_job}"
FILE_PATH="suites/smoke"
IS_ZPA_ENABLED="${zpa_enabled:=no}"

remove_all_last_logs_and_report_file

if [ ! -z ${deploy_type} ] && [ "${deploy_type}" == "gcp" ]; then
    case "$cloud" in
    "zscaler.net")
        cloud=zscaler.net
        cid=68219240
        cc_password=Admin@312
        zia_password=Admin@312
        asg_prov_url_name=rash-asg
        gcp_project=<GCP_PROJECT_ZSCALER_NET>
        gcp_region=us-central1
        gcp_secret_name=<SECRET_NAME_ZSCALER_NET>
        IS_ZPA_ENABLED=yes
        ;;
    "zscloud.net")
        cloud=zscloud.net
        cid=100652595
        cc_password=Zscaler@12345
        zia_password=Zscaler@12345
        asg_prov_url_name=jenkins-scheduler-asg
        gcp_project=<GCP_PROJECT_ZSCLOUD_NET>
        gcp_region=us-central1
        gcp_secret_name=<SECRET_NAME_ZSCLOUD_NET>
        IS_ZPA_ENABLED=yes
        ;;
    "zscalertwo.net")
        cloud=zscalertwo.net
        cid=59898399
        cc_password=Zscaler@312
        zia_password=Admin@123
        asg_prov_url_name=jenkins-scheduler-asg
        gcp_project=<GCP_PROJECT_ZSCALERTWO_NET>
        gcp_region=us-central1
        gcp_secret_name=<SECRET_NAME_ZSCALERTWO_NET>
        IS_ZPA_ENABLED=yes
        ;;
    "zscalerthree.net")
        cloud=zscalerthree.net
        cid=119094921
        cc_password=Admin@312
        zia_password=Admin@312
        asg_prov_url_name=jenkins-scheduler-asg
        gcp_project=<GCP_PROJECT_ZSCALERTHREE_NET>
        gcp_region=us-central1
        gcp_secret_name=<SECRET_NAME_ZSCALERTHREE_NET>
        IS_ZPA_ENABLED=yes
        ;;
    "zscalerbeta.net")
        cloud=zscalerbeta.net
        cid=11584588
        cc_password='Richaonly@123'
        zia_password='Richaonly@123'
        asg_prov_url_name=test1
        gcp_project=cc-qa-500
        gcp_region=asia-east1
        gcp_secret_name=projects/391445086918/secrets/zsbeta-st-7706126
        IS_ZPA_ENABLED=yes
        ;;
    "zsqa.net")
        cloud=zsqa.net
        cid=160323
        cc_password=Admin@123
        zia_password=Admin@123
        asg_prov_url_name=jenkins-scheduler-asg
        gcp_project=<GCP_PROJECT_ZSQA_NET>
        gcp_region=us-central1
        gcp_secret_name=<SECRET_NAME_ZSQA_NET>
        IS_ZPA_ENABLED=no
        ;;
    *)
        echo "Abort"
        exit 1
        ;;
    esac
    echo "Company ID: ${cid}"
    echo "Prov URL Name: ${asg_prov_url_name}"
    echo "GCP Project: ${gcp_project}"
    echo "GCP Region: ${gcp_region}"
fi

echo ${CI_PROJECT_DIR}
echo ${ZZTEST_WORKSPACE}
echo ${TERRAFORM_WORKSPACE}
echo ${WORKLOAD_SRE_WORKSPACE}

deploy_gcp_asg_setup() {
    if [ ! -z ${deploy_type} ] && [ "${deploy_type}" == "gcp" ]; then
        echo ">>>> Deploying ${deploy_type} ASG setup"
        echo "prov_url= connector.$cloud/api/v1/provUrl?name=${asg_prov_url_name}"
        echo "secret_name= ${gcp_secret_name}"
        echo "Use custom image?: ${image}"
        if [ "${image}" = "true" ] && [ -n "${image_name}" ]; then
            echo "Image override: ${image_name}"
        else
            echo "Image override: <not set — using default>"
        fi

        # Write GCP credentials JSON from CI variable to a temp file
        echo "${gcp_credentials_json}" > /tmp/gcp_credentials.json

        export TF_VAR_credentials=/tmp/gcp_credentials.json
        export TF_VAR_project=${gcp_project}
        export TF_VAR_region=${gcp_region}
        export TF_VAR_ccvm_instance_type=n2-standard-2
        export TF_VAR_cc_vm_prov_url="connector.${cloud}/api/v1/provUrl?name=${asg_prov_url_name}"
        export TF_VAR_secret_name=${gcp_secret_name}
        export TF_VAR_http_probe_port=50000
        export TF_VAR_az_count=1
        export TF_VAR_min_replicas=1
        export TF_VAR_max_replicas=2
        export TF_VAR_target_cpu_util_value=20
        export TF_VAR_byo_storage_bucket=false
        export TF_VAR_upload_cloud_function_zip=true
        export TF_VAR_cloud_function_source_object_name=cloud-functions-latest.zip
        export TF_VAR_cloud_function_source_object_path=./function_zip/cloud-functions-latest.zip
        export TF_VAR_grant_pubsub_editor=false
        export TF_VAR_support_access_enabled=true
        export TF_VAR_install_iperf=true
        export TF_VAR_name_prefix="cc-regr"
        export dtype=base_cc_asg

        # ─── image gate ───────────────────────────────────────────────────
        if [ "${image}" = "true" ] && [ -n "${image_name}" ]; then
            echo ">>>> Custom image requested: ${image_name}"
            export TF_VAR_ccvm_image_name="${image_name}"
        else
            if [ "${image}" = "true" ] && [ -z "${image_name}" ]; then
                echo ">>>> WARNING: image=true but image_name is empty. Using default image."
            else
                echo ">>>> image=false: using default image."
            fi
        fi
        # ─────────────────────────────────────────────────────────────────

        cd_dir ${TERRAFORM_WORKSPACE}/examples/base_cc_asg
        ${TERRAFORM_WORKSPACE}/examples/bin/terraform init
        ${TERRAFORM_WORKSPACE}/examples/bin/terraform apply -auto-approve
    fi
}

destroy_gcp_asg_setup() {
    local max_retries=3
    local retry_count=0
    local retry_delay=120  # seconds

    if [ ! -z ${deploy_type} ] && [ "${deploy_type}" == "gcp" ]; then
        echo ">>>> Destroy GCP ASG deployment"

        while [ $retry_count -lt $max_retries ]; do
            echo ">>>> Destroying... (attempt $((retry_count + 1)) of $max_retries)"
            cd_dir ${TERRAFORM_WORKSPACE}/examples/base_cc_asg
            output=$(${TERRAFORM_WORKSPACE}/examples/bin/terraform destroy -auto-approve 2>&1)
            echo "$output"

            if [[ "$output" =~ "Destroy complete!" ]]; then
                echo ">>>> Destroyed successfully"
                rm -f /tmp/gcp_credentials.json
                break
            else
                echo ">>>> Error destroying GCP ASG deployment (attempt $((retry_count + 1)) of $max_retries)"
                ((retry_count++))
                if [ $retry_count -lt $max_retries ]; then
                    echo ">>>> Retrying in $retry_delay seconds..."
                    sleep $retry_delay
                fi
            fi
        done

        if [ $retry_count -eq $max_retries ]; then
            echo ">>>> Failed to destroy GCP ASG deployment after $max_retries attempts"
            rm -f /tmp/gcp_credentials.json
        fi
    fi
}

if [ ! -z ${deploy_type} ] && [ "${deploy_type}" == "gcp" ] && [ "${asg_suite}" = true ]; then
    echo ">>>> Deploying GCP ASG deployment"
    deploy_gcp_asg_setup
    echo ">>>> Checking EC Instance Status"
    echo "Sleep 5m before checking the EC Instance Status"
    sleep 5m
    cd_dir ${CI_PROJECT_DIR}/cloned_repo
    tfstate_file=${TERRAFORM_WORKSPACE}/examples/terraform.tfstate
    echo "tfstate_file= ${tfstate_file}"
    python3 ${CI_PROJECT_DIR}/cloned_repo/src/utils/jenkins_script/asg_testbed_generator.py \
        --cloud $cloud \
        --cc_password $cc_password \
        --cid $cid \
        --tfstatefile_path $tfstate_file \
        --deploy_type gcp
    if [[ $? -eq 0 ]]; then
        echo ">>>> GCP ASG EC Deployment succeeded"
        echo ">>>> GCP testbed file generated."
        echo ">>>> Copying to ${ZZTEST_WORKSPACE}/suites/smoke/."
        cp gcp_testbed.yml ${ZZTEST_WORKSPACE}/suites/smoke/
        cd_dir ${TERRAFORM_WORKSPACE}/examples/base_cc_asg
        cp -p "$(ls *.pem -tr1 | tail -1)" "$ZZTEST_WORKSPACE/suites/smoke/"
        cd_dir $ZZTEST_WORKSPACE/suites/smoke/
        python3 ${CI_PROJECT_DIR}/cloned_repo/src/utils/jenkins_script/get_ec_asg_status.py \
            --deploy_type gcp \
            --gcp_project ${gcp_project} \
            --gcp_region ${gcp_region} \
            --gcp_credentials /tmp/gcp_credentials.json
        if [[ $? -eq 0 ]]; then
            echo "good to proceed with suite."
            pyats run job ${JOB_FILE} \
                --testbed="gcp_testbed.yml" \
                --html-logs=. \
                --testbed_cloud=gcp \
                --output_file test_output.json \
                --is_zpa_enabled no \
                --archive-dir=archive-dir \
                --archive-name=archive-file \
                --no-archive-subdir \
                --gcp_project ${gcp_project} \
                --gcp_region ${gcp_region}

            ARCHIVE_DIR=${ZZTEST_WORKSPACE}/suites/smoke/archive-dir
            ARCHIVE_NAME=archive-file
            JOB_FILE_PATH=${ZZTEST_WORKSPACE}/suites/smoke
            unzip -o ${ARCHIVE_DIR}/${ARCHIVE_NAME}.zip -d ${ARCHIVE_DIR}
            cd_dir ${ZZTEST_WORKSPACE}/src/utils/ec/
            python3 extract_test_details.py \
                --archive_file_name="${ARCHIVE_DIR}/results.json" \
                --output_file_name="${JOB_FILE_PATH}/test_output.json" \
                --generate_html_summary="yes" \
                --platform="gcp"
            copy_html_report_to_workspace
            cd_dir ${JOB_FILE_PATH}
            python3 ${CI_PROJECT_DIR}/cloned_repo/src/utils/jenkins_script/get_ec_asg_status.py --cleanup
            destroy_gcp_asg_setup
            exit 0
        else
            python3 ${CI_PROJECT_DIR}/cloned_repo/src/utils/jenkins_script/get_ec_asg_status.py --cleanup
            destroy_gcp_asg_setup
            exit 1
        fi
    else
        python3 ${CI_PROJECT_DIR}/cloned_repo/src/utils/jenkins_script/get_ec_asg_status.py --cleanup
        destroy_gcp_asg_setup
        exit 1
    fi
fi
