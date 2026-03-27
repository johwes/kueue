# Demo: Priorities - Production Workloads

This demo shows how production inference workloads share resources with training workloads, demonstrating fair sharing between teams.

## Prerequisites

- Module 01 setup (00-setup) complete
- LocalQueue `ml-inference-queue` exists in `ml-inference` namespace
- Recommended: Complete [01-demo-fair-sharing](../01-demo-fair-sharing/) first

---

## Production Workloads

This directory contains production inference jobs:

| Job | CPUs | Memory | Duration | Description |
|-----|------|--------|----------|-------------|
| `job-batch-customer-inference.yaml` | 1 | 256Mi | ~70s | Production batch predictions for customers |
| `job-model-validation.yaml` | 2 | 256Mi | ~90s | Pre-production model validation |
| `job-feature-extraction.yaml` | 1 | 128Mi | ~60s | Batch embedding generation |

---

## Demo: Fair Sharing Between Teams

This scenario demonstrates the core value of Kueue - ensuring production workloads get resources even when training saturates the cluster.

### The Setup

1. Training jobs run first and saturate most of the cluster
2. Production inference job arrives
3. Kueue ensures production gets its fair share

### Step-by-Step

**Step 1: Saturate cluster with training jobs**

```bash
# Submit training jobs first
cd ../01-demo-fair-sharing
oc apply -f jobs/

# Verify training is using resources
oc get workload -n ml-training
```

Expected: 2 training jobs admitted (4 CPUs), 1 queued (needs 2 more)

**Step 2: Production job arrives**

```bash
# Submit production inference job
cd ../02-demo-priorities
oc apply -f jobs/job-batch-customer-inference.yaml

# Check if it got admitted
oc get workload -n ml-inference
```

**Expected:**
```
NAME                                       QUEUE                ADMITTED   AGE
job-job-batch-customer-inference-xxxxx    ml-inference-queue   True       2s
```

**KEY OBSERVATION:** Production job admitted immediately! Even though training saturated most resources, production got the available 1 CPU.

**Step 3: View both teams sharing resources**

```bash
# Monitor workloads across both namespaces
oc get workload -n ml-training -n ml-inference
```

**Expected:**
```
NAMESPACE      NAME                                    QUEUE                ADMITTED
ml-inference   job-batch-customer-inference-xxxxx     ml-inference-queue   True
ml-training    job-finetune-llm-xxxxx                 ml-training-queue    True
ml-training    job-hyperparameter-tuning-xxxxx        ml-training-queue    True
ml-training    job-train-resnet-model-xxxxx           ml-training-queue
```

**Resource Distribution:**
- Training: 4 CPUs (LLM 3 + Hyperparameter 1)
- Inference: 1 CPU (Batch inference)
- Total: 5 CPUs (quota fully utilized)
- Queued: ResNet training (waiting for 2 CPUs)

**Step 4: Watch automatic fair sharing**

```bash
# Watch as jobs complete and resources redistribute
watch -n 2 "oc get workload -n ml-training -n ml-inference"
```

When jobs complete:
1. Hyperparameter (60s) or Inference (70s) finishes first
2. Resources freed
3. Queued ResNet job automatically admitted
4. Both teams eventually complete their workloads

---

## What This Demonstrates

✅ **No Production Starvation:** Production got resources despite training running first

✅ **Fair Resource Sharing:** Both queues get their share of the cluster

✅ **Automatic Balancing:** No manual intervention needed

✅ **Queue Independence:** Each team submits to their own queue

---

## Comparing: With vs. Without Kueue

### Without Kueue (Standard Kubernetes)

```
1. Training jobs start first → consume all CPUs
2. Production job arrives → pods stay "Pending" forever
3. Engineer manually kills training jobs → wastes work
4. Production runs → completes
5. Training resubmitted → starts from scratch
Result: Manual intervention, wasted resources, frustrated teams
```

### With Kueue (This Demo)

```
1. Training jobs start first → admitted based on quota
2. Production job arrives → gets fair share immediately
3. Both teams' jobs run and complete successfully
4. No manual intervention needed
Result: Automatic fair sharing, efficient resource use, happy teams
```

---

## Advanced Scenario: Priority Preemption

**Note:** This demo shows fair sharing, but doesn't have priority-based preemption. For that advanced feature, see [Module 02: Borrowing & Preemption](../../02-borrowing-preemption/).

In Module 02, you'll learn:
- How to assign priority classes to jobs
- How high-priority jobs can preempt low-priority jobs
- How to implement checkpointing for resumable training

---

## Cleanup

```bash
# Delete all jobs in both namespaces
oc delete jobs --all -n ml-training
oc delete jobs --all -n ml-inference

# Verify clean state
oc get clusterqueue cluster-total
```

---

## Key Commands Reference

```bash
# View workloads across both namespaces
oc get workload -n ml-training -n ml-inference

# Check resource utilization
oc get clusterqueue cluster-total -o json | \
  jq '.status.flavorsReservation[0].resources'

# Monitor in real-time
watch -n 2 "oc get workload -A"

# Check queue status
oc get localqueue -A
```

---

## Next Steps

After completing this module, you have two paths:

**Path 1: Learn Monitoring**
→ [Module 03: Monitoring](../../03-monitoring/) - Monitor queue health and resource utilization

**Path 2: Learn Advanced Features**
→ [Module 02: Borrowing & Preemption](../../02-borrowing-preemption/) - Resource borrowing, priorities, and checkpointing

---

## What You Learned

✅ How production and training workloads share resources
✅ How Kueue prevents production starvation
✅ How to monitor multi-team resource usage
✅ The value of automatic fair sharing vs. manual intervention
