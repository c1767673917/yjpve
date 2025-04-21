from flask import Flask, render_template, request, jsonify, redirect, url_for
import subprocess
import os
import json
import time
import threading
from functools import wraps

app = Flask(__name__)
app.secret_key = os.urandom(24)

# 存储命令输出的字典
command_outputs = {}
# 存储后台进程的字典
processes = {}

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        # 这里应该添加真正的认证逻辑
        # 简单起见，这里只是返回原函数
        return f(*args, **kwargs)
    return decorated

def run_command(command, output_key, callback=None):
    """运行命令并将输出存储到字典中"""
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        shell=True,
        text=True,
        bufsize=1,
        universal_newlines=True
    )
    
    processes[output_key] = process
    command_outputs[output_key] = []
    
    for line in iter(process.stdout.readline, ''):
        command_outputs[output_key].append(line)
        if callback:
            callback(line)
    
    process.stdout.close()
    return_code = process.wait()
    
    if return_code == 0:
        command_outputs[output_key].append("命令执行成功!")
    else:
        command_outputs[output_key].append(f"命令执行失败，返回代码: {return_code}")
    
    del processes[output_key]
    
    if callback:
        callback(None)  # 发送完成信号

@app.route('/')
@requires_auth
def index():
    return render_template('index.html')

@app.route('/check_pve')
def check_pve():
    """检查是否安装了PVE"""
    result = subprocess.run("command -v qm", shell=True, capture_output=True, text=True)
    if result.returncode == 0:
        return jsonify({"installed": True})
    else:
        return jsonify({"installed": False})

@app.route('/vm_list')
def vm_list():
    """获取虚拟机列表"""
    result = subprocess.run("qm list", shell=True, capture_output=True, text=True)
    if result.returncode == 0:
        lines = result.stdout.strip().split('\n')
        if len(lines) > 1:
            headers = lines[0].split()
            vms = []
            for line in lines[1:]:
                values = line.split()
                vm = {}
                for i, header in enumerate(headers):
                    if i < len(values):
                        vm[header] = values[i]
                vms.append(vm)
            return jsonify({"success": True, "vms": vms})
    return jsonify({"success": False, "error": "获取虚拟机列表失败"})

@app.route('/create_vm', methods=['POST'])
def create_vm():
    """创建虚拟机"""
    data = request.form
    vmid = data.get('vmid')
    username = data.get('username')
    password = data.get('password')
    cpu = data.get('cpu', '1')
    memory = data.get('memory', '512')
    disk = data.get('disk', '10')
    full_port = data.get('full_port', 'N')
    
    if full_port.upper() == 'Y':
        ssh_port = str(40000 + int(vmid))
        http_port = str(41000 + int(vmid))
        https_port = str(42000 + int(vmid))
        port_start = "1025"
        port_end = "65535"
    else:
        ssh_port = data.get('ssh_port', str(40000 + int(vmid)))
        http_port = data.get('http_port', str(41000 + int(vmid)))
        https_port = data.get('https_port', str(42000 + int(vmid)))
        port_start = data.get('port_start', '50000')
        port_end = data.get('port_end', str(int(port_start) + 25))
    
    os_template = data.get('os', 'debian11')
    storage = data.get('storage', 'local')
    ipv6 = data.get('ipv6', 'N')
    
    # 检查buildvm.sh是否存在，不存在则下载
    if not os.path.exists("buildvm.sh"):
        subprocess.run("curl -L https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/buildvm.sh -o buildvm.sh && chmod +x buildvm.sh", shell=True)
    
    # 构建命令
    command = f"./buildvm.sh {vmid} {username} {password} {cpu} {memory} {disk} {ssh_port} {http_port} {https_port} {port_start} {port_end} {os_template} {storage} {ipv6}"
    
    # 启动后台线程执行命令
    output_key = f"create_vm_{int(time.time())}"
    threading.Thread(target=run_command, args=(command, output_key)).start()
    
    return jsonify({"success": True, "output_key": output_key})

@app.route('/delete_vm', methods=['POST'])
def delete_vm():
    """删除虚拟机"""
    vmid = request.form.get('vmid')
    
    # 检查pve_delete.sh是否存在，不存在则下载
    if not os.path.exists("pve_delete.sh"):
        subprocess.run("curl -L https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/pve_delete.sh -o pve_delete.sh && chmod +x pve_delete.sh", shell=True)
    
    # 构建命令
    command = f"./pve_delete.sh {vmid}"
    
    # 启动后台线程执行命令
    output_key = f"delete_vm_{int(time.time())}"
    threading.Thread(target=run_command, args=(command, output_key)).start()
    
    return jsonify({"success": True, "output_key": output_key})

@app.route('/delete_all_vms', methods=['POST'])
def delete_all_vms():
    """删除所有虚拟机"""
    confirm = request.form.get('confirm')
    
    if confirm != 'yes':
        return jsonify({"success": False, "error": "请输入'yes'确认删除所有虚拟机"})
    
    # 获取所有VM ID
    result = subprocess.run("qm list | awk '{if(NR>1) print $1}'", shell=True, capture_output=True, text=True)
    vm_ids = result.stdout.strip().split('\n')
    
    # 构建命令
    commands = []
    for vmid in vm_ids:
        if vmid:
            commands.append(f"qm stop {vmid} && qm destroy {vmid}")
    
    commands.append("iptables -t nat -F")
    commands.append("iptables -t filter -F")
    commands.append("service networking restart")
    commands.append("systemctl restart networking.service")
    commands.append("iptables-save | awk '{if($1==\"COMMIT\"){delete x}}$1==\"-A\"?!x[$0]++:1' | iptables-restore")
    
    full_command = " && ".join(commands)
    
    # 启动后台线程执行命令
    output_key = f"delete_all_{int(time.time())}"
    threading.Thread(target=run_command, args=(full_command, output_key)).start()
    
    return jsonify({"success": True, "output_key": output_key})

@app.route('/optimize_env', methods=['POST'])
def optimize_env():
    """优化PVE环境"""
    # 检查build_backend.sh是否存在，不存在则下载
    if not os.path.exists("build_backend.sh"):
        is_cn = subprocess.run("curl -sm 3 https://www.baidu.com > /dev/null 2>&1 && echo 'cn' || echo 'global'", 
                              shell=True, capture_output=True, text=True).stdout.strip()
        
        if is_cn == 'cn':
            url = "https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh"
        else:
            url = "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh"
        
        subprocess.run(f"curl -L {url} -o build_backend.sh && chmod +x build_backend.sh", shell=True)
    
    # 构建命令
    command = "./build_backend.sh"
    
    # 启动后台线程执行命令
    output_key = f"optimize_{int(time.time())}"
    threading.Thread(target=run_command, args=(command, output_key)).start()
    
    return jsonify({"success": True, "output_key": output_key})

@app.route('/command_output/<output_key>')
def command_output(output_key):
    """获取命令输出"""
    if output_key in command_outputs:
        output = command_outputs[output_key]
        is_running = output_key in processes
        return jsonify({"success": True, "output": output, "running": is_running})
    else:
        return jsonify({"success": False, "error": "无效的输出键"})

@app.route('/batch_create', methods=['POST'])
def batch_create():
    """批量创建虚拟机"""
    # 检查create_vm.sh是否存在，不存在则下载
    if not os.path.exists("create_vm.sh"):
        subprocess.run("curl -L https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/create_vm.sh -o create_vm.sh && chmod +x create_vm.sh", shell=True)
    
    # 确保screen已安装
    subprocess.run("command -v screen > /dev/null || apt-get update && apt-get install -y screen", shell=True)
    
    # 构建命令
    use_screen = request.form.get('use_screen', 'Y')
    
    if use_screen.upper() == 'Y':
        command = "screen -S pve_batch_vm -dm bash -c 'bash create_vm.sh; exec bash'"
        subprocess.run(command, shell=True)
        return jsonify({
            "success": True, 
            "message": "批量创建已在screen会话中启动，使用 'screen -r pve_batch_vm' 查看进度"
        })
    else:
        command = "./create_vm.sh"
        output_key = f"batch_create_{int(time.time())}"
        threading.Thread(target=run_command, args=(command, output_key)).start()
        return jsonify({"success": True, "output_key": output_key})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True) 