#!/usr/bin/env bash
set -euo pipefail

# As a Kubernetes administrator, set up a namespace
# where the k8s-gitlab-admins have full access

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab
  labels:
    name: gitlab
    smallstep.com/inject: enabled
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gitlab-admin
  namespace: gitlab
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: oidc-gitlab
  namespace: gitlab
subjects:
- kind: Group
  name: oidc:k8s-gitlab-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: gitlab-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gitlab-vault-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: gitlab-auth-config
    namespace: gitlab
EOF