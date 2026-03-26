# Setup Notes for Red Hat Build of Kueue on OpenShift

## Key Configuration Requirements

### 1. Operator Subscription Channel
The Red Hat Build of Kueue operator requires a specific channel version:
- **Incorrect**: `channel: stable`
- **Correct**: `channel: stable-v1.3` (or latest stable-v1.x)

Check available channels:
```bash
oc get packagemanifest kueue-operator -o jsonpath='{.status.channels[*].name}'
```

### 2. Kueue Instance Creation
After the operator is installed, you must create a `Kueue` CR to deploy the controller:

```yaml
apiVersion: kueue.openshift.io/v1
kind: Kueue
metadata:
  name: cluster
spec:
  config:
    integrations:
      frameworks:
      - BatchJob
  managementState: Managed
```

This is different from upstream Kueue where the controller is deployed automatically.

### 3. Namespace Labeling
Namespaces containing Kueue-managed workloads MUST have the label:
```yaml
kueue.openshift.io/managed: "true"
```

This label enables the Kueue mutating webhook to process jobs in that namespace.

Example:
```bash
oc label namespace team-alpha kueue.openshift.io/managed=true
```

### 4. Job Suspension
Jobs must be created with `suspend: true` to allow Kueue to manage their admission:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-job
  labels:
    kueue.x-k8s.io/queue-name: my-queue
spec:
  suspend: true  # <-- Required!
  template:
    # ... job spec
```

Kueue will automatically unsuspend the job when resources are available.

### 5. API Version
The current API version is `kueue.x-k8s.io/v1beta2` (not v1beta1).

## Installation Checklist

- [ ] Install Red Hat Build of Kueue operator with correct channel
- [ ] Create Kueue CR instance
- [ ] Verify controller pods are running
- [ ] Create ResourceFlavors, ClusterQueues, LocalQueues
- [ ] Label namespaces with `kueue.openshift.io/managed=true`
- [ ] Submit jobs with `suspend: true` and queue labels
- [ ] Verify workloads are created and admitted

## Verification Commands

```bash
# Check operator installation
oc get csv -n openshift-operators | grep kueue

# Check Kueue instance
oc get kueue cluster

# Check controller pods
oc get pods -n openshift-operators | grep kueue-controller

# Check CRDs
oc api-resources | grep kueue.x-k8s.io

# Check namespaces are labeled
oc get namespace team-alpha -o jsonpath='{.metadata.labels}'

# Check workloads
oc get workload -A

# Check ClusterQueue status
oc describe clusterqueue cluster-total
```

## Common Issues

### Jobs Not Creating Workloads
**Symptom**: Jobs are created but no Workload objects appear

**Causes**:
1. Namespace missing `kueue.openshift.io/managed=true` label
2. Job created without `suspend: true`
3. Job missing `kueue.x-k8s.io/queue-name` label

### CSV Installation Fails
**Symptom**: Subscription exists but CSV never appears

**Cause**: Wrong channel specified in subscription

**Fix**: Use specific version channel like `stable-v1.3`

### Controller Pods Not Starting
**Symptom**: Operator installed but no kueue-controller-manager pods

**Cause**: Kueue CR instance not created

**Fix**: Create the Kueue CR as shown above

## Testing the Setup

```bash
# Deploy a simple test job
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: test-job
  namespace: team-alpha
  labels:
    kueue.x-k8s.io/queue-name: team-alpha-queue
spec:
  suspend: true
  template:
    spec:
      containers:
      - name: test
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["echo", "Hello from Kueue!"]
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
      restartPolicy: Never
EOF

# Check workload was created
oc get workload -n team-alpha

# Check job was admitted
oc describe workload -n team-alpha job-test-job-xxxxx
```
