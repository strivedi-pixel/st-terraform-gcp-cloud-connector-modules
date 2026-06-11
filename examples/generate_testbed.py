import json
import subprocess
import os
import re

def get_terraform_output():
    try:
        # Assuming we are in the examples directory
        result = subprocess.run(
            ["./bin/terraform", "-chdir=base_cc_asg", "output", "-json"],
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except Exception as e:
        print(f"Error running terraform output: {e}")
        return None

def parse_testbedconfig(config_str):
    data = {}
    
    # Parse Workload IPs
    workload_ips = re.findall(r"workload-(\d+) = ([\d\.]+)", config_str)
    data['workloads'] = [{"name": f"workload-{i}", "ip": ip} for i, ip in workload_ips]
    
    # Parse Bastion IP
    bastion_ip_match = re.search(r"BASTION Public IP: \s+([\d\.]+)", config_str)
    if bastion_ip_match:
        data['bastion_ip'] = bastion_ip_match.group(1)
        
    # Parse SSH Key
    key_match = re.search(r"zscc-key-([\w]+)\.pem", config_str)
    if key_match:
        data['ssh_key'] = f"zscc-key-{key_match.group(1)}.pem"
        
    # Parse Iperf IP
    iperf_ip_match = re.search(r"IPERF Server Details:.*?Private IP:\s+([\d\.]+)", config_str, re.DOTALL)
    if iperf_ip_match:
        data['iperf_private_ip'] = iperf_ip_match.group(1)

    return data

def generate_pyats_testbed(data, output_file="testbed.yaml"):
    testbed_content = f"""
testbed:
  name: GCP-CC-Testbed
  credentials:
    default:
      username: ubuntu
      ssh_key: {data.get('ssh_key', 'zscc-key.pem')}

devices:
"""
    # Add Bastion
    if 'bastion_ip' in data:
        testbed_content += f"""
  bastion:
    type: bastion
    os: linux
    connections:
      defaults:
        class: unicon.ssh3.SshConnection
      vty:
        ip: {data['bastion_ip']}
"""

    # Add Workloads
    for workload in data.get('workloads', []):
        name = workload['name']
        testbed_content += f"""
  {name}:
    type: workload
    os: linux
    connections:
      defaults:
        class: unicon.ssh3.SshConnection
      vty:
        ip: {workload['ip']}
        proxy: bastion
"""

    # Add Iperf Server
    if 'iperf_private_ip' in data:
        testbed_content += f"""
  iperf-server:
    type: iperf
    os: linux
    connections:
      defaults:
        class: unicon.ssh3.SshConnection
      vty:
        ip: {data['iperf_private_ip']}
        proxy: bastion
"""

    with open(output_file, 'w') as f:
        f.write(testbed_content)
    print(f"Generated pyATS testbed at {output_file}")

if __name__ == "__main__":
    outputs = get_terraform_output()
    if outputs and 'testbedconfig' in outputs:
        config_str = outputs['testbedconfig']['value']
        data = parse_testbedconfig(config_str)
        generate_pyats_testbed(data)
    else:
        print("Could not find testbedconfig in terraform outputs.")
