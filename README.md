# SaltStack自动化部署HA-Kubernetes
- SaltStack自动化部署Kubernetes v1.16.9版本（支持TLS双向认证、RBAC授权、Flannel网络、ETCD集群、Kuber-Proxy使用LVS等）。网络使用host-gw的模式。

## 版本明细：Release-v1.16.9
- 测试通过系统：CentOS 7.4
- salt-ssh:     2017.7.4
- Kubernetes：  v1.16.9
- Etcd:         v3.3.1
- Docker-CE:    19.03.8-ce
- Flannel：     v0.10.0
- CNI-Plugins： v0.7.0
- nginx: v1.16.1
建议部署节点：最少三个节点，请配置好主机名解析（必备）。

## 架构介绍
1. 使用Salt Grains进行角色定义，增加灵活性。
2. 使用Salt Pillar进行配置项管理，保证安全性。
3. 使用Salt SSH执行状态，不需要安装Agent，保证通用性。
4. 使用Kubernetes当前稳定版本v1.16.9，保证稳定性。
5. 使用nginx来保证集群的高可用性。
6. 本文的高可用可通用于任何云上的SDN环境和自建机房环境，例如阿里云的VPC环境中。

## 特别感谢
1. 写这个新的搭建步骤主要是方便使用和排错，对网络做了些调整。
2. 感谢devops学院推出的salt自动化搭建k8s流程https://github.com/unixhot/salt-kubernetes
3. 感谢SaltStack自动化部署HA-Kubernetes https://github.com/skymyyang/salt-k8s-ha.git

# 使用手册
<table border="0">
    <tr>
        <td><strong>手动部署</strong></td>
        <td><a href="docs/init.md">1.系统初始化</a></td>
        <td><a href="docs/ca.md">2.CA证书制作</a></td>
        <td><a href="docs/etcd-install.md">3.ETCD集群部署</a></td>
        <td><a href="docs/master.md">4.Master节点部署</a></td>
        <td><a href="docs/node.md">5.Node节点部署</a></td>
        <td><a href="docs/flannel.md">6.Flannel部署</a></td>
        <td><a href="docs/app.md">7.应用创建</a></td>
    </tr>
    <tr>
        <td><strong>必备插件</strong></td>
        <td><a href="docs/coredns.md">1.CoreDNS部署</a></td>
        <td><a href="docs/dashboard.md">2.Dashboard部署</a></td>
        <td><a href="docs/heapster.md">3.Heapster部署</a></td>
        <td><a href="docs/ingress.md">4.Ingress部署</a></td>
        <td><a href="https://github.com/unixhot/devops-x">5.CI/CD</a></td>
        <td><a href="docs/helm.md">6.Helm部署</a></td>
    </tr>
</table>

## 案例架构图

  ![架构图](https://github.com/ziyilongwang/k8s-salt/blob/master/docs/K8S.png)

## 0.系统初始化(必备)
1. 设置主机名！！！
```
[root@linux-node1 ~]# cat /etc/hostname 
linux-node1.example.com

[root@linux-node2 ~]# cat /etc/hostname 
linux-node2.example.com

[root@linux-node3 ~]# cat /etc/hostname 
linux-node3.example.com

```
2. 设置/etc/hosts保证主机名能够解析
```
[root@linux-node1 ~]# cat /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
192.168.56.11 linux-node1 linux-node1.example.com
192.168.56.12 linux-node2 linux-node2.example.com
192.168.56.13 linux-node3 linux-node3.example.com

```
3. 关闭SELinux和防火墙
```
systemctl disable firewalld NetworkManager
systemctl stop firewalld NetworkManager
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g'  /etc/selinux/config 
```
4. 更新yum源
[root@linux-node1 ~]# rpm -ivh http://mirrors.aliyun.com/epel/epel-release-latest-7.noarch.rpm
5. 安装一些依赖包
[root@linux-node1 ~]# yum install -y net-tools vim lrzsz screen lsof tcpdump nc mtr nmap wget


4. 优化内核参数

   ```bash
   # For more information, see sysctl.conf(5) and sysctl.d(5).
   net.ipv6.conf.all.disable_ipv6 = 1
   net.ipv6.conf.default.disable_ipv6 = 1
   net.ipv6.conf.lo.disable_ipv6 = 1
   
   vm.swappiness = 0
   net.ipv4.neigh.default.gc_stale_time=120
   net.ipv4.ip_forward = 1
   
   # see details in https://help.aliyun.com/knowledge_detail/39428.html
   net.ipv4.conf.all.rp_filter=0
   net.ipv4.conf.default.rp_filter=0
   net.ipv4.conf.default.arp_announce = 2
   net.ipv4.conf.lo.arp_announce=2
   net.ipv4.conf.all.arp_announce=2
   
   
   # see details in https://help.aliyun.com/knowledge_detail/41334.html
   net.ipv4.tcp_max_tw_buckets = 5000
   net.ipv4.tcp_syncookies = 1
   net.ipv4.tcp_max_syn_backlog = 1024
   net.ipv4.tcp_synack_retries = 2
   kernel.sysrq = 1
   
   #iptables透明网桥的实现
   # NOTE: kube-proxy 要求 NODE 节点操作系统中要具备 /sys/module/br_netfilter 文件，而且还要设置 bridge-nf-call-iptables=1，如果不满足要求，那么 kube-proxy 只是将检查信息记录到日志中，kube-proxy 仍然会正常运行，但是这样通过 Kube-proxy 设置的某些 iptables 规则就不会工作。
   
   net.bridge.bridge-nf-call-ip6tables = 1
   net.bridge.bridge-nf-call-iptables = 1
   net.bridge.bridge-nf-call-arptables = 1
   
   ```

   5.以上必备条件必须严格检查，否则，一定不会部署成功！

## 1.设置部署节点到其它所有节点的SSH免密码登录（包括本机）
```bash
[root@linux-node1 ~]# ssh-keygen -t rsa
[root@linux-node1 ~]# ssh-copy-id linux-node1
[root@linux-node1 ~]# ssh-copy-id linux-node2
[root@linux-node1 ~]# ssh-copy-id linux-node3
```

## 2.安装Salt-SSH并克隆本项目代码。

2.1 安装Salt SSH（注意：老版本的Salt SSH不支持Roster定义Grains，需要2017.7.4以上版本）
```
[root@linux-node1 ~]# yum install https://mirrors.aliyun.com/epel/epel-release-latest-7.noarch.rpm
[root@linux-node1 ~]# yum install https://mirrors.aliyun.com/saltstack/yum/redhat/salt-repo-latest-2.el7.noarch.rpm
[root@linux-node1 ~]# sed -i "s/repo.saltstack.com/mirrors.aliyun.com\/saltstack/g" /etc/yum.repos.d/salt-latest.repo
[root@linux-node1 ~]# yum install -y salt-ssh git unzip
```

2.2 获取本项目代码，并放置在/srv目录
```
[root@linux-node1 ~]# git clone https://github.com/ziyilongwang/k8s-salt.git
[root@linux-node1 ~]# cd k8s-salt/
[root@linux-node1 ~]# mv * /srv/
[root@linux-node1 srv]# /bin/cp /srv/roster /etc/salt/roster
[root@linux-node1 srv]# /bin/cp /srv/master /etc/salt/master
```

2.4 下载二进制文件，也可以自行官方下载，为了方便国内用户访问，请在百度云盘下载,下载k8s-v1.15.2.tar.gz。
下载完成后，将文件移动到/srv/salt/k8s/目录下，并解压
Kubernetes二进制文件下载地址： https://pan.baidu.com/s/1-ZxmZ0LFrGQJVPXQLu1apQ

```
[root@linux-node1 ~]# cd /srv/salt/k8s/
[root@linux-node1 k8s]# tar -xzvf k8s-v1.15.2.tar.gz
[root@linux-node1 k8s]# rm -f k8s-v1.15.2.tar.gz
[root@linux-node1 k8s]# ls -l files/
total 0
drwxr-xr-x. 2 root root  94 Jun  3 19:12 cfssl-1.2
drwxr-xr-x. 2 root root 195 Jun  3 19:12 cni-plugins-amd64-v0.7.0
drwxr-xr-x. 2 root root  33 Jun  3 19:12 etcd-v3.3.1-linux-amd64
drwxr-xr-x. 2 root root  47 Jun  3 19:12 flannel-v0.10.0-linux-amd64
drwxr-xr-x. 3 root root  17 Jun  3 19:12 k8s-v1.15.2

```

## 3.Salt SSH管理的机器以及角色分配

- k8s-role-master: 用来设置K8S的master角色
- k8s-role-node: 用来设置k8s的node角色
- etcd-role: 用来设置etcd的角色，如果只需要部署一个etcd，只需要在一台机器上设置即可
- etcd-name: 如果对一台机器设置了etcd-role就必须设置etcd-name


```
[root@linux-node1 ~]# vim /etc/salt/roster 
linux-node1:
  host: 192.168.56.11
  user: root
  priv: /root/.ssh/id_rsa
  minion_opts:
    grains:
      k8s-role-master: master
      etcd-role: node
      etcd-name: etcd-node1

linux-node2:
  host: 192.168.56.12
  user: root
  priv: /root/.ssh/id_rsa
  minion_opts:
    grains:
      k8s-role-master: master
      k8s-role-node: node
      etcd-role: node
      etcd-name: etcd-node2

linux-node3:
  host: 192.168.56.13
  user: root
  priv: /root/.ssh/id_rsa
  minion_opts:
    grains:
      k8s-role-master: master
      k8s-role-node: node
      etcd-role: node
      etcd-name: etcd-node3
```

## 4.修改对应的配置参数，本项目使用Salt Pillar保存配置
```
[root@linux-node1 ~]# vim /srv/pillar/k8s.sls
#设置Master的IP地址(必须修改)
MASTER_IP_M1: "192.168.56.11"
MASTER_IP_M2: "192.168.56.12"
MASTER_IP_M3: "192.168.56.13"

#KUBE-APISERVER的反向代理地址端口
KUBE_APISERVER: "https://127.0.0.1:8443"

#设置ETCD集群访问地址（必须修改）
ETCD_ENDPOINTS: "https://192.168.56.11:2379,https://192.168.56.12:2379,https://192.168.56.13:2379"

#设置ETCD集群初始化列表（必须修改）
ETCD_CLUSTER: "etcd-node1=https://192.168.56.11:2380,etcd-node2=https://192.168.56.12:2380,etcd-node3=https://192.168.56.13:2380"

#通过Grains FQDN自动获取本机IP地址，请注意保证主机名解析到本机IP地址
NODE_IP: {{ grains['fqdn_ip4'][0] }}

#设置BOOTSTARP的TOKEN，可以自己生成
BOOTSTRAP_TOKEN: "ad6d5bb607a186796d8861557df0d17f"

#配置Service IP地址段
SERVICE_CIDR: "10.1.0.0/16"

#Kubernetes服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_KUBERNETES_SVC_IP: "10.1.0.1"

#Kubernetes DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP: "10.1.0.2"

#设置Node Port的端口范围,可自定义
NODE_PORT_RANGE: "20000-40000"

#设置POD的IP地址段
POD_CIDR: "10.2.0.0/16"

#设置集群的DNS域名
CLUSTER_DNS_DOMAIN: "cluster.local."

```

## 5.执行SaltStack状态

5.1 测试Salt SSH联通性
```
[root@linux-node1 ~]# salt-ssh '*' test.ping
```
执行高级状态，会根据定义的角色再对应的机器部署对应的服务

5.2 重新生成ca证书，并替换templates下面的ca文件夹，参考手动制作CA证书步骤,并将证书进行替换
```
cd /tmp/
curl -L https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o cfssl
chmod +x cfssl
curl -L https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o cfssljson
chmod +x cfssljson
curl -L https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -o cfssl-certinfo
chmod +x cfssl-certinfo
mkdir /tmp/cert
cd /tmp/cert
cp /srv/salt/k8s/templates/ca/*json .
../cfssl gencert -initca ca-csr.json | ../cfssljson -bare ca
\cp -f  * /srv/salt/k8s/templates/ca/
```

5.3 部署Etcd，由于Etcd是基础组建，需要先部署，目标为部署etcd的节点。
```
[root@linux-node1 ~]# salt-ssh -L 'linux-node1,linux-node2,linux-node3' state.sls k8s.etcd
```
注：如果执行失败，新手建议推到重来，请检查各个节点的主机名解析是否正确（监听的IP地址依赖主机名解析）。



5.4 部署K8S集群
```
[root@linux-node1 ~]# salt-ssh '*' state.highstate
```
由于包比较大，这里执行时间较长，5分钟+，喝杯咖啡休息一下，如果执行有失败可以再次执行即可！

## 6.测试Kubernetes安装
```
[root@linux-node1 ~]# source /etc/profile
[root@linux-node1 ~]# kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok                  
controller-manager   Healthy   ok                  
etcd-0               Healthy   {"health":"true"}   
etcd-2               Healthy   {"health":"true"}   
etcd-1               Healthy   {"health":"true"}   
[root@linux-node1 ~]# kubectl get node
NAME            STATUS    ROLES     AGE       VERSION
192.168.56.12   Ready     <none>    1m        v1.10.3
192.168.56.13   Ready     <none>    1m        v1.10.3
```
## 7.测试Kubernetes集群和Flannel网络

```
[root@linux-node1 ~]# kubectl run net-test --image=alpine --replicas=2 sleep 360000
deployment "net-test" created
需要等待拉取镜像，可能稍有的慢，请等待。
[root@linux-node1 ~]# kubectl get pod -o wide
NAME                        READY     STATUS    RESTARTS   AGE       IP          NODE
net-test-5767cb94df-n9lvk   1/1       Running   0          14s       10.2.12.2   192.168.56.13
net-test-5767cb94df-zclc5   1/1       Running   0          14s       10.2.24.2   192.168.56.12

测试联通性，如果都能ping通，说明Kubernetes集群部署完毕，有问题请QQ群交流。
[root@linux-node1 ~]# ping -c 1 10.2.12.2
PING 10.2.12.2 (10.2.12.2) 56(84) bytes of data.
64 bytes from 10.2.12.2: icmp_seq=1 ttl=61 time=8.72 ms

--- 10.2.12.2 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 8.729/8.729/8.729/0.000 ms

[root@linux-node1 ~]# ping -c 1 10.2.24.2
PING 10.2.24.2 (10.2.24.2) 56(84) bytes of data.
64 bytes from 10.2.24.2: icmp_seq=1 ttl=61 time=22.9 ms

--- 10.2.24.2 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 22.960/22.960/22.960/0.000 ms


确认服务能够执行 logs exec 等指令;kubectl logs -f net-test-5767cb94df-n9lvk,此时会出现如下报错:
[root@linux-node1 ~]# kubectl logs net-test-5767cb94df-n9lvk
error: You must be logged in to the server (the server has asked for the client to provide credentials ( pods/log net-test-5767cb94df-n9lvk))


由于上述权限问题，我们必需创建一个 apiserver-to-kubelet-rbac.yml 来定义权限，以供我们执行 logs、exec 等指令;
[root@linux-node1 ~]# kubectl apply -f /srv/addons/apiserver-to-kubelet-rbac.yml
然后执行kubctl logs验证是否成功.
```
## 8.如何新增Kubernetes节点

- 1.设置SSH无密码登录
- 2.在/etc/salt/roster里面，增加对应的机器
- 3.执行SaltStack状态salt-ssh '*' state.highstate。
```
[root@linux-node1 ~]# vim /etc/salt/roster 
linux-node4:
  host: 192.168.56.14
  user: root
  priv: /root/.ssh/id_rsa
  minion_opts:
    grains:
      k8s-role: node
[root@linux-node1 ~]# salt-ssh 'linux-node4' state.highstate
```

## 9.下一步要做什么？

你可以安装Kubernetes必备的插件
<table border="0">
    <tr>
        <td><strong>必备插件</strong></td>
        <td><a href="docs/coredns.md">1.CoreDNS部署</a></td>
        <td><a href="docs/dashboard.md">2.Dashboard部署</a></td>
        <td><a href="docs/heapster.md">3.Heapster部署</a></td>
        <td><a href="docs/ingress.md">4.Ingress部署</a></td>
        <td><a href="https://github.com/unixhot/devops-x">5.CI/CD</a></td>
    </tr>
</table>

注意：不要相信自己，要相信电脑！！！

# 手动部署
- [系统初始化](docs/init.md)
- [CA证书制作](docs/ca.md)
- [ETCD集群部署](docs/etcd-install.md)
- [Master节点部署](docs/master.md)
- [Node节点部署](docs/node.md)
- [Flannel网络部署](docs/flannel.md)
- [创建第一个K8S应用](docs/app.md)
- [CoreDNS和Dashboard部署](docs/dashboard.md)

# ci

- [持续集成](docs/ci.md)
