#!/bin/bash
# 1. Mise à jour et dépendances système
apt-get update
apt-get install -y curl fuse3 open-iscsi nfs-common

# 2. Optimisation Kernel pour Plex
echo "fs.inotify.max_user_instances=524288" >> /etc/sysctl.d/99-kubernetes.conf
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.d/99-kubernetes.conf
sysctl -p /etc/sysctl.d/99-kubernetes.conf

# 3. Préparation du dossier d'auto-déploiement K3s
mkdir -p /var/lib/rancher/k3s/server/manifests/

# 4. Injection du HelmChart ArgoCD (Sera lu par K3s au démarrage)
cat <<EOF > /var/lib/rancher/k3s/server/manifests/argocd.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: argocd
  namespace: kube-system
spec:
  chart: argo-cd
  repo: https://argoproj.github.io/argo-helm
  targetNamespace: argocd
  createNamespace: true
  valuesContent: |-
    server:
      extraArgs:
        - --insecure
    configs:
      params:
        server.insecure: true
EOF

# 5. Récupération de l'IP publique
PUBLIC_IP=$(curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4)

# 6. Installation de K3s (Déclenche le démarrage et l'installation d'ArgoCD)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san $PUBLIC_IP --write-kubeconfig-mode 644" sh -s -