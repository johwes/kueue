# Module 02: Workloads

This module demonstrates how to submit jobs to Kueue-managed queues and observe resource allocation and queueing behavior.

## Overview

In this module, you'll:
1. Submit jobs from team-alpha and team-beta
2. Observe queue admission and resource allocation
3. See queueing behavior when resources are exhausted
4. Understand workload priorities
5. Monitor job execution and completion

## Workload Types

We provide several example workloads:

### Team Alpha Workloads
- `job-data-processing.yaml` - Simulates data processing (2 CPUs, 4Gi memory)
- `job-model-training.yaml` - Simulates ML training (3 CPUs, 6Gi memory)
- `job-batch-analysis.yaml` - Simulates batch job (1 CPU, 2Gi memory)

### Team Beta Workloads
- `job-integration-test.yaml` - Simulates testing (1 CPU, 2Gi memory)
- `job-build.yaml` - Simulates CI/CD build (2 CPUs, 3Gi memory)
- `job-validation.yaml` - Simulates validation (1 CPU, 1Gi memory)

## How Jobs Work with Kueue

### Standard Kubernetes Job
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-job
spec:
  template:
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["sh", "-c", "echo Hello"]
      restartPolicy: Never
```

### Kueue-Enabled Job
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-job
  labels:
    kueue.x-k8s.io/queue-name: team-alpha-queue  # ← Add this label!
spec:
  template:
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["sh", "-c", "echo Hello"]
        resources:                                 # ← Specify resources
          requests:
            cpu: "1"
            memory: "1Gi"
      restartPolicy: Never
```

**Key Differences:**
1. **Queue Label**: `kueue.x-k8s.io/queue-name` specifies which LocalQueue to submit to
2. **Resource Requests**: Must specify CPU/memory requests for admission control

## Demo Scenario 1: Basic Queueing

Submit jobs and observe basic queueing:

```bash
# Submit team-alpha jobs
oc apply -f team-alpha/job-data-processing.yaml
oc apply -f team-alpha/job-model-training.yaml

# Watch workloads
watch -n 2 "oc get workload -n team-alpha"

# Watch jobs
watch -n 2 "oc get jobs -n team-alpha"
```

Expected behavior:
1. Jobs create Workload objects automatically
2. Kueue evaluates workloads against queue quotas
3. Admitted workloads start running
4. Pending workloads wait in queue

## Demo Scenario 2: Resource Exhaustion

Saturate the cluster to see queueing behavior:

```bash
# Submit multiple jobs from both teams
oc apply -f team-alpha/
oc apply -f team-beta/

# Monitor cluster queue status
watch -n 2 "oc describe clusterqueue cluster-total"

# Monitor workloads across all namespaces
watch -n 2 "oc get workload -A"
```

Expected behavior:
1. First jobs are admitted until quota is exhausted
2. Additional jobs enter "Pending" state
3. As jobs complete, pending workloads are admitted
4. Resources are distributed fairly between teams

## Demo Scenario 3: Job Lifecycle

Follow a single job through its lifecycle:

```bash
# Submit a job
oc apply -f team-alpha/job-data-processing.yaml

# Watch workload status
oc get workload -n team-alpha -w

# Describe workload for detailed status
oc describe workload -n team-alpha job-data-processing-xxxxx

# Watch pod creation
oc get pods -n team-alpha -w

# Check job completion
oc get job -n team-alpha job-data-processing
```

Lifecycle stages:
1. **Job Created** → Workload object created
2. **Workload Admitted** → Resources reserved, pods can be created
3. **Pods Running** → Containers executing
4. **Job Complete** → Workload finished, resources released
5. **Cleanup** → Workload can be deleted (or retained for history)

## Understanding Workload Objects

Kueue creates a Workload object for each Job:

```bash
oc get workload -n team-alpha
```

View workload details:
```bash
oc describe workload -n team-alpha <workload-name>
```

Key information:
- **Admitted**: Whether the workload has resources allocated
- **Conditions**: Admission status, reasons for pending
- **Resource Requests**: CPU, memory requested
- **Priority**: If using WorkloadPriorityClasses
- **Queue**: LocalQueue the workload is in

## Cleaning Up Completed Jobs

After jobs complete:

```bash
# Delete all jobs in team-alpha
oc delete jobs --all -n team-alpha

# Delete all jobs in team-beta
oc delete jobs --all -n team-beta

# Or delete specific job
oc delete job job-data-processing -n team-alpha
```

Note: Deleting a Job also deletes its associated Workload object.

## Testing Fair Sharing

To observe fair sharing between teams:

```bash
# Start monitoring in separate terminal
watch -n 2 "oc get workload -A"

# Terminal 1: Submit many team-alpha jobs
for i in {1..5}; do
  cat team-alpha/job-data-processing.yaml | sed "s/job-data-processing/job-alpha-$i/" | oc apply -f -
done

# Terminal 2: Submit many team-beta jobs
for i in {1..5}; do
  cat team-beta/job-integration-test.yaml | sed "s/job-integration-test/job-beta-$i/" | oc apply -f -
done
```

Observe how Kueue distributes resources fairly between the teams.

## Common Workload States

| State | Meaning |
|-------|---------|
| **QuotaReserved=True** | Resources allocated, workload can run |
| **QuotaReserved=False** | Waiting for resources |
| **Admitted=True** | Workload is running or has run |
| **Finished=True** | Workload completed |

Check conditions:
```bash
oc get workload -n team-alpha <name> -o jsonpath='{.status.conditions}' | jq
```

## Troubleshooting

### Job not creating Workload

**Problem**: Job created but no Workload appears

**Check**:
```bash
# Verify queue label
oc get job <job-name> -n team-alpha -o yaml | grep queue-name

# Verify LocalQueue exists
oc get localqueue -n team-alpha
```

**Solution**: Ensure job has `kueue.x-k8s.io/queue-name` label

### Workload stuck in Pending

**Problem**: Workload never gets admitted

**Check**:
```bash
# Check workload status
oc describe workload -n team-alpha <workload-name>

# Check ClusterQueue status
oc describe clusterqueue cluster-total
```

**Common causes**:
- Insufficient resources in ClusterQueue
- LocalQueue not mapped to ClusterQueue
- Resource requests exceed quota

### Pods not starting despite admitted Workload

**Problem**: Workload is admitted but pods don't start

**Check**:
```bash
# Check pod events
oc get events -n team-alpha --sort-by='.lastTimestamp'

# Check pod status
oc describe pod <pod-name> -n team-alpha
```

**Common causes**:
- Node resource constraints (actual cluster capacity vs. Kueue quota)
- Image pull failures
- Security context issues

## Job Templates

All job templates follow this pattern:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-name
  namespace: team-namespace
  labels:
    kueue.x-k8s.io/queue-name: queue-name
spec:
  template:
    spec:
      containers:
      - name: worker
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["sh", "-c"]
        args:
        - |
          echo "Starting work..."
          sleep 30  # Simulate work
          echo "Work complete!"
        resources:
          requests:
            cpu: "1"
            memory: "1Gi"
      restartPolicy: Never
  backoffLimit: 2
```

## Next Steps

Once you've experimented with workloads, proceed to [03-monitoring](../03-monitoring/README.md) to learn about monitoring and troubleshooting tools.

## Additional Resources

- [Kueue Workload Documentation](https://kueue.sigs.k8s.io/docs/concepts/workload/)
- [Running Jobs with Kueue](https://kueue.sigs.k8s.io/docs/tasks/run_jobs/)
- [Kubernetes Jobs Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
