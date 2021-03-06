# -*- coding: utf-8 -*-
#******************************************
# Author:       zhanglong
# Email:        392572435@qq.com
# Organization: http://www.devopsedu.com/
# Description:  Kubernetes Master
#******************************************
include:
  - k8s.modules.nginx
  - k8s.modules.ca-file
  - k8s.modules.cfssl
  - k8s.modules.cni
  - k8s.modules.api-server
  - k8s.modules.controller-manager
  - k8s.modules.scheduler
  - k8s.modules.kubectl
  - k8s.modules.flannel
  - k8s.modules.docker
