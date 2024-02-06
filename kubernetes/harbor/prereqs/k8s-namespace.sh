#!/usr/bin/env bash
set -euo pipefail

# As a Kubernetes administrator, set up a namespace
# where the k8s-harbor-admins have full access

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
  labels:
    name: harbor
    smallstep.com/inject: enabled
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: harbor-admin
  namespace: harbor
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
  name: oidc-harbor
  namespace: harbor
subjects:
- kind: Group
  name: oidc:k8s-harbor-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: harbor-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: harbor-vault-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: harbor-auth-config
    namespace: harbor
EOF