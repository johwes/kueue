# Module 02: Workloads

This module demonstrates the real-world scenario: **ML training experiments competing with production inference workloads for shared GPU resources**.

## The Scenario

Your organization runs all ML workloads on a shared GPU cluster due to the high cost of GPU infrastructure. Two teams submit jobs to this cluster:

### ML Training Team (Experimentation)
**Goal**: Train and improve ML models through experimentation

**Workloads**:
- `job-train-resnet-model.yaml` - Training ResNet-50 for image classification (2 CPU, 256Mi memory)
- `job-finetune-llm.yaml` - Fine-tuning a large language model (3 CPU, 512Mi memory)
- `job-hyperparameter-tuning.yaml` - Running hyperparameter optimization (1 CPU, 128Mi memory)

**Characteristics**:
- Unpredictable submission times
- Variable duration (hours to days)
- Can tolerate queueing delays
- Innovation-focused, not time-critical

### ML Inference Team (Production)
**Goal**: Serve customer-facing ML predictions with SLA guarantees

**Workloads**:
- `job-batch-customer-inference.yaml` - Production batch predictions for customers (1 CPU, 256Mi memory)
- `job-model-validation.yaml` - Pre-production model validation (2 CPU, 256Mi memory)
- `job-feature-extraction.yaml` - Batch embedding generation (1 CPU, 128Mi memory)

**Characteristics**:
- Predictable, scheduled submission
- Time-sensitive with SLA requirements
- Cannot be starved of resources
- Customer-impacting, production-critical

## The Problem Without Kueue

**Before implementing Kueue**, this scenario leads to conflicts:

1. **Resource Starvation**: Training jobs consume all GPUs at 2 AM, blocking morning inference batch jobs
2. **SLA Breaches**: Production inference delayed, customers experience degraded service
3. **Manual Intervention**: Engineers manually kill training jobs to free resources
4. **Wasted Resources**: GPUs sit idle when training is killed, then saturated when training resumes
5. **Team Friction**: Training team vs. Inference team conflicts over resource priority

## The Solution With Kueue

**After implementing Kueue**, resource sharing becomes automatic:

1. **Fair Queueing**: Training and inference workloads share resources fairly
2. **Production Priority**: Inference workloads get admitted even when training saturates cluster
3. **Efficient Utilization**: Training uses idle capacity without blocking production
4. **Visibility**: Teams can see queue depth and admission status
5. **Automatic**: No manual intervention required

## How Jobs Work with Kueue

### Standard Kubernetes Job (Without Kueue)
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-training-job
spec:
  template:
    spec:
      containers:
      - name: trainer
        image: my-ml-image
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
      restartPolicy: Never
```
**Problem**: This job runs immediately, potentially starving production workloads.

### Kueue-Managed Job
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-training-job
  labels:
    kueue.x-k8s.io/queue-name: ml-training-queue  # ← Routes to training queue
spec:
  suspend: true  # ← Kueue controls when it starts
  template:
    spec:
      containers:
      - name: trainer
        image: my-ml-image
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
      restartPolicy: Never
```
**Solution**: Kueue queues this job and admits it when resources are available without impacting production.

**Key Differences**:
1. **Queue Label**: `kueue.x-k8s.io/queue-name` specifies which LocalQueue (training vs inference)
2. **Suspend**: `suspend: true` lets Kueue control admission
3. **Resource Requests**: Required for Kueue to calculate quota usage

## Demo Scenario 1: Training Fills the Cluster

This scenario demonstrates **queueing in action**. The cluster has only 5 CPUs available, but we'll submit 3 training jobs requesting 6 CPUs total (2+3+1). This forces at least one job to wait in queue.

### Resource Math
- **Available quota**: 5 CPUs, 2Gi memory
- **Training jobs requesting**:
  - ResNet training: 2 CPU, 256Mi
  - LLM fine-tuning: 3 CPU, 512Mi
  - Hyperparameter tuning: 1 CPU, 128Mi
  - **Total**: 6 CPU, 896Mi (CPU exceeds quota!)

### Step-by-Step Walkthrough

**Step 1: Check initial cluster state (before submitting jobs)**

```bash
# Verify the cluster queue is empty
oc get clusterqueue cluster-total -o wide

# Check resource availability
oc get clusterqueue cluster-total -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources}' | jq
```

Expected output:
```
NAME            COHORT   STRATEGY         PENDING WORKLOADS   ADMITTED WORKLOADS
cluster-total            BestEffortFIFO   0                   0
```

This shows the cluster is ready with no workloads.

---

**Step 2: Submit all training jobs at once**

```bash
# Submit all 3 training jobs
oc apply -f ml-training/

# Immediately check what jobs were created
oc get jobs -n ml-training
```

Expected output:
```
NAME                          COMPLETIONS   DURATION   AGE
job-finetune-llm              0/1                      5s
job-hyperparameter-tuning     0/1                      5s
job-train-resnet-model        0/1                      5s
```

Notice: All jobs are created with **COMPLETIONS 0/1** and remain suspended.

---

**Step 3: Check Workload objects (Kueue's admission control)**

```bash
# List all workloads in ml-training namespace
oc get workload -n ml-training
```

Expected output (wait ~10 seconds after job creation):
```
NAME                                     QUEUE               ADMITTED   AGE
job-finetune-llm-xxxxx                  ml-training-queue   True       20s
job-train-resnet-model-xxxxx            ml-training-queue   True       20s
job-hyperparameter-tuning-xxxxx         ml-training-queue   False      20s
```

**KEY OBSERVATION**:
- ✅ **2 jobs ADMITTED** (ResNet + LLM = 5 CPUs, 10Gi - exactly fills quota!)
- ⏳ **1 job PENDING** (Hyperparameter tuning waiting for resources)

---

**Step 4: Verify which jobs are actually running**

```bash
# Check job status
oc get jobs -n ml-training

# Check if pods are running for admitted jobs
oc get pods -n ml-training
```

Expected output:
```
NAME                          COMPLETIONS   DURATION   AGE
job-finetune-llm              0/1           30s        1m
job-train-resnet-model        0/1           30s        1m
job-hyperparameter-tuning     0/1                      1m    ← Still suspended!
```

You should see pods running for ResNet and LLM jobs, but NO pods for hyperparameter-tuning because it's still queued.

---

**Step 5: Check ClusterQueue utilization**

```bash
# Show detailed resource usage
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation[0].resources'
```

Expected output:
```json
[
  {
    "name": "cpu",
    "total": "5",
    "borrowed": "0",
    "used": "5"        ← CPU quota fully utilized!
  },
  {
    "name": "memory",
    "total": "2Gi",
    "borrowed": "0",
    "used": "768Mi"    ← Memory usage (minimal for demo cost-efficiency)
  }
]
```

**This proves**: The cluster CPU quota is at capacity - no resources available for the queued job.

---

**Step 6: Describe the queued workload to see why it's waiting**

```bash
# Find the pending workload name
PENDING_WORKLOAD=$(oc get workload -n ml-training -o json | jq -r '.items[] | select(.status.admission == null) | .metadata.name')

# Describe it to see the reason
oc describe workload -n ml-training $PENDING_WORKLOAD
```

Look for the **Conditions** section:
```
Conditions:
  Type:                QuotaReserved
  Status:              False
  Reason:              Pending
  Message:             couldn't assign flavors to pod set main: insufficient quota...
```

**This explains**: The workload is waiting because there's no quota available.

---

**Step 7: Watch the queue admission when a job completes**

Open a monitoring window:
```bash
# In Terminal 1: Watch workloads
watch -n 2 "oc get workload -n ml-training"

# In Terminal 2: Watch the ClusterQueue
watch -n 2 "oc get clusterqueue cluster-total"
```

**Wait for one of the running jobs to complete** (~2-3 minutes for these demo jobs).

**What you'll observe**:
1. When ResNet job completes → resources released (5 CPUs → 3 CPUs used)
2. Queued hyperparameter job immediately admitted (3 CPUs → 4 CPUs used)
3. The queued job transitions from `ADMITTED=False` to `ADMITTED=True`
4. Pods start for the previously queued job

---

**Step 8: Verify the lifecycle**

```bash
# Check final status of all workloads
oc get workload -n ml-training

# Check which jobs completed
oc get jobs -n ml-training
```

Expected progression:
```
NAME                                QUEUE               ADMITTED   AGE
job-train-resnet-model-xxxxx       ml-training-queue   True       5m    ← Completed
job-finetune-llm-xxxxx             ml-training-queue   True       5m    ← Still running
job-hyperparameter-tuning-xxxxx    ml-training-queue   True       5m    ← Now admitted!
```

---

### What You Just Learned

✅ **Queueing in action**: When quota is exhausted, jobs wait in queue
✅ **Automatic admission**: As resources free up, queued jobs are automatically admitted
✅ **Resource accounting**: Kueue tracks exactly how much quota is used
✅ **Transparency**: You can see why jobs are pending and when they'll be admitted

### Key Commands Summary

```bash
# See which jobs are admitted vs pending
oc get workload -n ml-training

# Check cluster capacity and usage
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation'

# See why a workload is pending
oc describe workload -n ml-training <workload-name>

# Monitor in real-time
watch -n 2 "oc get workload -n ml-training"
```

## Demo Scenario 2: Production Needs Guaranteed Access

Now simulate a production inference job arriving while training saturates the cluster:

```bash
# Training is already running (from Scenario 1)
# Submit production inference job
oc apply -f ml-inference/job-batch-customer-inference.yaml

# Watch it compete for resources
watch -n 2 "oc get workload -A"

# Monitor fair sharing
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation'
```

**Expected Behavior**:
1. Production job creates a Workload in ml-inference namespace
2. Kueue evaluates against the same ClusterQueue
3. Resources are shared fairly between training and inference queues
4. Both workload types get their fair share

**Key Insight**: Even though training filled the cluster first, production inference gets resources through fair sharing.

## Demo Scenario 3: Complete Lifecycle

Follow a single job through its complete lifecycle:

```bash
# Submit a training job
oc apply -f ml-training/job-hyperparameter-tuning.yaml

# Watch workload status changes
oc get workload -n ml-training -w

# In another terminal, watch the job
oc get job -n ml-training job-hyperparameter-tuning -w

# Check pod logs when running
oc logs -n ml-training -l app=hyperparameter-tuning -f
```

**Lifecycle Stages**:
1. **Job Created** (suspend: true) → Workload object created
2. **Workload Queued** → Waiting for resources
3. **Workload Admitted** → Resources reserved, job unsuspended
4. **Pods Running** → Containers executing
5. **Job Complete** → Workload finished, resources released
6. **Cleanup** → Workload marked as finished

## Understanding Workload Objects

Kueue creates a Workload object for each Job to manage admission:

```bash
# List workloads across both namespaces
oc get workload -A

# Describe a specific workload
oc describe workload -n ml-training <workload-name>
```

**Key Fields**:
- **spec.queueName**: Which LocalQueue this workload belongs to
- **spec.podSets**: Resource requests for the job
- **status.admission**: If admitted, shows assigned resources
- **status.conditions**: Admission status and reasons

Example:
```bash
oc get workload -n ml-training job-job-train-resnet-model-xxxxx -o yaml
```

## Demonstrating Fair Sharing

To see fair sharing in action, saturate both queues:

```bash
# Terminal 1: Monitor overall status
watch -n 2 "oc get workload -A && echo '' && oc get clusterqueue"

# Terminal 2: Submit all training jobs
oc apply -f ml-training/

# Terminal 3: Submit all inference jobs  
oc apply -f ml-inference/
```

**Observations**:
- Total cluster quota: 5 CPUs, 2Gi memory
- Both queues compete for the same resources (CPU is the limiting factor)
- Kueue ensures fair distribution
- Neither queue is completely starved
- Resources are allocated dynamically as jobs complete

**Note**: Memory requests are kept minimal (128Mi-512Mi) for cost efficiency at scale. CPU quota is the primary resource being demonstrated.

## Production vs. Training Priority (Advanced)

For production SLA guarantees, you can configure priority:

**Step 1**: Create WorkloadPriorityClasses (not included in basic demo):
```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata:
  name: production-critical
spec:
  value: 1000
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata:
  name: training-experimental
spec:
  value: 100
```

**Step 2**: Reference in jobs:
```yaml
metadata:
  labels:
    kueue.x-k8s.io/priority-class: production-critical
```

**Result**: Production jobs can preempt lower-priority training jobs when necessary.

## Common Workload States

| Condition | Meaning |
|-----------|---------|
| **QuotaReserved=True** | Resources allocated, workload can run |
| **QuotaReserved=False** | Waiting for resources, queued |
| **Admitted=True** | Workload is running or has run |
| **Finished=True** | Workload completed successfully |
| **Evicted=True** | Workload was preempted by higher priority |

Check workload conditions:
```bash
oc get workload -n ml-training <name> -o jsonpath='{.status.conditions}' | jq
```

## Cleaning Up Completed Jobs

After experimentation:

```bash
# Delete all jobs in ml-training
oc delete jobs --all -n ml-training

# Delete all jobs in ml-inference
oc delete jobs --all -n ml-inference

# Or delete specific jobs
oc delete job job-train-resnet-model -n ml-training
```

**Note**: Deleting a Job automatically deletes its associated Workload object.

## Troubleshooting

### Job Created But No Workload Appears

**Problem**: Job exists but no Workload object created

**Diagnosis**:
```bash
# Check job labels
oc get job <job-name> -n ml-training -o yaml | grep -A 5 labels

# Check namespace label
oc get namespace ml-training -o jsonpath='{.metadata.labels}'
```

**Common Causes**:
1. Missing `kueue.x-k8s.io/queue-name` label on Job
2. Namespace missing `kueue.openshift.io/managed=true` label
3. Job not created with `suspend: true`

**Solution**: Ensure all three requirements are met.

### Workload Stuck in Pending

**Problem**: Workload never gets admitted

**Diagnosis**:
```bash
# Check workload status
oc describe workload -n ml-training <workload-name>

# Check cluster queue capacity
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation'
```

**Common Causes**:
1. Cluster quota exhausted (all resources in use)
2. Job requests more resources than total quota
3. LocalQueue not properly mapped to ClusterQueue

### Pods Not Starting Despite Admitted Workload

**Problem**: Workload admitted but pods don't appear

**Diagnosis**:
```bash
# Check events
oc get events -n ml-training --sort-by='.lastTimestamp'

# Check job status
oc describe job <job-name> -n ml-training
```

**Common Causes**:
1. Actual node capacity less than Kueue quota (nodes don't have enough CPU/memory)
2. Image pull errors
3. Pod security policies blocking pod creation

## What You've Learned

By completing this module, you've seen:

✅ **Real-world ML scenario**: Training vs. production inference competing for GPUs  
✅ **Fair resource sharing**: Both workload types get their fair share  
✅ **Queue management**: Automatic admission control without manual intervention  
✅ **Workload lifecycle**: From creation to admission to completion  
✅ **Visibility**: Clear view of queue status and resource allocation  

## Next Steps

Proceed to [03-monitoring](../03-monitoring/README.md) to learn:
- How to monitor queue health
- Track resource utilization
- Verify production SLAs are met
- Troubleshoot resource contention

## Key Takeaway

**Before Kueue**: Manual intervention required to prevent training from starving production.  
**With Kueue**: Automatic fair sharing ensures both innovation (training) and reliability (production) coexist.
