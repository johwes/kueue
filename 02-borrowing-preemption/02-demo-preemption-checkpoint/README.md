# Demo 2: Preemption with Checkpoint Resume

This demo demonstrates **preemption** - how high-priority production workloads can reclaim resources from low-priority training jobs, and how training jobs survive preemption using **checkpointing**.

## The Scenario

**Setup:**
- Training job is running using **borrowed** resources (using 5 CPUs: 3 own + 2 borrowed from inference)
- Training job is **low-priority** (can be preempted)
- Training job has **checkpointing** enabled (saves progress to PVC)

**Event:**
- Production inference job arrives (high-priority)
- Needs 2 CPUs immediately for customer SLA

**Challenge:**
- Inference's 2 CPUs are currently borrowed by training
- How does inference get its resources back?

**Solution: Preemption**
1. Inference triggers preemption of training job
2. Training job is evicted (pod deleted)
3. Training's checkpoint survives on PVC (progress saved!)
4. Inference runs with reclaimed resources
5. When inference completes, training is readmitted
6. Training resumes from last checkpoint - no work lost!

---

## Understanding Checkpointing

### Without Checkpointing (Work Lost)
```
Training progress: 0% → 10% → 20% → 30% [PREEMPTED]
After readmission: 0% → 10% → 20% → 30% → ... (RESTART FROM 0%)
Result: 30% of work WASTED
```

### With Checkpointing (Work Preserved)
```
Training progress: 0% → 10% → 20% → 30% [PREEMPTED, saves "30" to PVC]
After readmission: Resume from 30% → 35% → 40% → ... → 100%
Result: NO work wasted, seamless resume!
```

---

## Step-by-Step Walkthrough

### Step 1: Verify Checkpoint PVC Exists

```bash
# Check PVC status
oc get pvc -n ml-training training-checkpoint-pvc
```

Expected output:
```
NAME                        STATUS   VOLUME                    CAPACITY   ACCESS MODES
training-checkpoint-pvc     Bound    pvc-xxxxx-xxxx-xxxx       100Mi      RWO
```

If STATUS is "Pending", wait or check troubleshooting section.

---

### Step 2: Submit Low-Priority Training Job with Checkpoint

```bash
cd 03-demo-preemption-checkpoint

# Submit training job that uses borrowed resources
oc apply -f jobs/training-checkpoint.yaml

# Watch it start
oc get workload,job -n ml-training
```

Expected output:
```
NAME                                          QUEUE               RESERVED IN              ADMITTED   AGE
workload.../job-training-checkpoint-xxxxx    ml-training-queue   training-cluster-queue   True       2s

NAME                                STATUS    COMPLETIONS   DURATION   AGE
job.batch/training-checkpoint       Running   0/1           2s         3s
```

---

### Step 3: Monitor Checkpointing in Action

Open **two terminals** to observe the checkpoint file and job logs:

**Terminal 1 - Watch checkpoint progress:**
```bash
# This shows the checkpoint file being updated
watch -n 2 "oc exec -n ml-training \$(oc get pods -n ml-training -l app=training-checkpoint -o name) -- cat /workspace/checkpoint/training-progress.log 2>/dev/null | tail -5"
```

**Terminal 2 - Follow job logs:**
```bash
oc logs -n ml-training -l app=training-checkpoint -f
```

Expected output in Terminal 1 (checkpoint file):
```
0     ← Initial state
5     ← After 10 seconds
10    ← After 20 seconds
15    ← After 30 seconds
20    ← Growing over time...
```

Expected output in Terminal 2 (job logs):
```
==========================================
Training with Checkpointing Enabled
==========================================
🆕 Starting fresh training from 0%
🔄 Training progress: 5% (epoch 1)
🔄 Training progress: 10% (epoch 2)
🔄 Training progress: 15% (epoch 3)
🔄 Training progress: 20% (epoch 4)
...
```

**Let the training run for ~30-40 seconds** (reaching 20-25% progress).

---

### Step 4: Trigger Preemption with High-Priority Inference Job

While training is running (at ~20-25% progress), submit high-priority inference:

**Terminal 3 - Submit preempting job:**
```bash
# This high-priority inference job will preempt training
oc apply -f jobs/inference-preempt.yaml

# Watch preemption happen
oc get events -n ml-training --sort-by='.lastTimestamp' | tail -20
```

Expected events:
```
LAST SEEN   TYPE      REASON       OBJECT                          MESSAGE
5s          Normal    Evicted      workload/job-training-checkpoint  Preempted to reclaim resources
4s          Normal    Suspended    job/training-checkpoint          Job suspended due to preemption
3s          Normal    Deleted      pod/training-checkpoint-xxxxx    Pod deleted by Kueue
2s          Normal    Admitted     workload/job-inference-preempt   Admitted to inference-cluster-queue
```

---

### Step 5: Verify Training Job Was Preempted

```bash
# Check training job status (should be Suspended)
oc get job training-checkpoint -n ml-training

# Check workload status (should show Evicted)
oc get workload -n ml-training
```

Expected output:
```
Job status:
NAME                    STATUS      COMPLETIONS   DURATION   AGE
training-checkpoint     Suspended   0/1                      2m   ← Suspended!

Workload status:
NAME                              QUEUE             ADMITTED   EVICTED   AGE
job-training-checkpoint-xxxxx    ml-training-queue            True      2m
                                                              ^^^^
                                                              Evicted = True
```

---

### Step 6: Verify Checkpoint Survived Preemption

Even though the pod was deleted, the checkpoint persists on PVC:

```bash
# Create a temporary pod to read the checkpoint file
oc run checkpoint-reader --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --restart=Never -n ml-training --rm -i --tty \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "reader",
      "image": "registry.access.redhat.com/ubi9/ubi-minimal:latest",
      "command": ["cat", "/workspace/checkpoint/training-progress.log"],
      "volumeMounts": [{
        "name": "checkpoint",
        "mountPath": "/workspace/checkpoint"
      }]
    }],
    "volumes": [{
      "name": "checkpoint",
      "persistentVolumeClaim": {"claimName": "training-checkpoint-pvc"}
    }]
  }
}' -- cat /workspace/checkpoint/training-progress.log
```

Expected output:
```
0
5
10
15
20    ← Last checkpoint before preemption!
```

**This proves:** Training had reached 20% before being preempted, and progress is saved!

---

### Step 7: Watch Inference Job Run

```bash
# Monitor inference job (should be running now)
oc get job -n ml-inference

# View inference logs
oc logs -n ml-inference -l app=inference-preempt -f
```

Expected output:
```
NAME                    STATUS    COMPLETIONS   DURATION   AGE
inference-preempt       Running   0/1           10s        12s

Logs:
==========================================
Production Inference: High Priority
==========================================
Preempted training job to reclaim resources
Running critical customer inference...
Processing batch 1/5...
Processing batch 2/5...
...
Inference complete!
==========================================
```

Inference completes in ~60 seconds.

---

### Step 8: Watch Training Auto-Resume from Checkpoint

After inference completes, training is automatically readmitted:

```bash
# Watch for training readmission
watch -n 2 "oc get workload,job -n ml-training"
```

Expected progression:
```
# After inference completes (~60s):
workload.../job-training-checkpoint-xxxxx    ml-training-queue   training-cluster-queue   True    3m
                                                                                         ^^^^
                                                                                         Readmitted!

job.batch/training-checkpoint                Running             0/1           5s         3m
                                             ^^^^^^^
                                             Resumed!
```

---

### Step 9: Verify Resume from Checkpoint

Watch the training logs to see it resume from 20%:

```bash
oc logs -n ml-training -l app=training-checkpoint -f
```

**CRITICAL OUTPUT:**
```
==========================================
Training with Checkpointing Enabled
==========================================
📦 Loaded checkpoint: 20
📊 Resuming from checkpoint: 20%         ← KEY MOMENT!
🔄 Training progress: 25% (epoch 5)      ← Continues from 20%, not 0%!
🔄 Training progress: 30% (epoch 6)
🔄 Training progress: 35% (epoch 7)
...
✅ Training complete: 100%
==========================================
```

**This proves:**
- Training resumed from 20% (last checkpoint)
- No work was lost due to preemption
- Training completed successfully to 100%

---

### Step 10: Verify Final State

```bash
# Check both jobs completed
oc get job -n ml-training -n ml-inference

# Check final checkpoint value
oc run checkpoint-final --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --restart=Never -n ml-training --rm -i --tty \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "reader",
      "image": "registry.access.redhat.com/ubi9/ubi-minimal:latest",
      "command": ["tail", "/workspace/checkpoint/training-progress.log"],
      "volumeMounts": [{
        "name": "checkpoint",
        "mountPath": "/workspace/checkpoint"
      }]
    }],
    "volumes": [{
      "name": "checkpoint",
      "persistentVolumeClaim": {"claimName": "training-checkpoint-pvc"}
    }]
  }
}' -- tail -5 /workspace/checkpoint/training-progress.log
```

Expected output:
```
80
85
90
95
100   ← Training reached 100% successfully!
```

---

## What You Just Learned

✅ **Preemption in Action:** High-priority job evicted low-priority job to reclaim resources

✅ **Checkpointing Pattern:** Training saved progress to PVC before eviction

✅ **Automatic Resume:** Training readmitted and resumed from checkpoint after inference completed

✅ **No Work Lost:** Training continued from 20% (not 0%) after preemption

✅ **Production SLAs Met:** Inference got resources immediately, completed successfully

✅ **Efficient Resource Use:** Training completed eventually, using 95%+ of cluster capacity

---

## Timeline Analysis

Let's break down what happened:

```
Time  Event                                 Training    Inference   Total CPUs
────────────────────────────────────────────────────────────────────────────────
0:00  Training starts                       5 CPUs      0 CPUs      5/5 (100%)
      (borrows 2 from inference)

0:30  Training reaches 20% progress         5 CPUs      0 CPUs      5/5 (100%)
      Checkpoint saved: "20"

0:35  Inference arrives (high-priority)     5 CPUs      NEEDS 2!    Conflict!

0:36  PREEMPTION TRIGGERED                  [EVICTED]   -           -
      - Training workload marked Evicted
      - Training pod deleted
      - Checkpoint survives on PVC

0:37  Inference admitted                    0 CPUs      2 CPUs      2/5 (40%)
      (reclaimed its 2 CPUs from training)

1:37  Inference completes (60s runtime)     0 CPUs      0 CPUs      0/5 (0%)
      Resources freed

1:38  Training readmitted automatically     3 CPUs      0 CPUs      3/5 (60%)
      (no borrowing this time)

1:39  Training resumes from checkpoint      3 CPUs      0 CPUs      3/5 (60%)
      Reads "20" from PVC
      Continues from 20% → 100%

4:00  Training completes                    0 CPUs      0 CPUs      0/5 (0%)
      Final checkpoint: "100"
```

**Total time:** ~4 minutes
**Work preserved:** 20% completed before preemption
**Wasted work:** 0%
**Production SLA:** Met (inference ran immediately)

---

## Understanding Preemption Policies

The preemption behavior is controlled by ClusterQueue configuration:

```yaml
# From clusterqueue-inference.yaml
preemption:
  reclaimWithinCohort: Any  # Can reclaim borrowed resources from training
```

**What this means:**
- Inference can evict workloads that borrowed its quota
- Training borrowed 2 CPUs from inference
- When inference needs those 2 CPUs back → preemption

**Preemption Priority:**
1. **Within same queue:** `high-priority` (1000) > `low-priority` (100)
2. **Across queues in cohort:** Nominal quota owner can reclaim borrowed resources
3. **Protection:** Jobs using only their nominal quota cannot be preempted for borrowing

---

## Checkpoint Implementation Details

The checkpoint script used in `training-checkpoint.yaml`:

```bash
#!/bin/bash
PVC_PATH="/workspace/checkpoint"
LOGFILE="$PVC_PATH/training-progress.log"

# Initialize if first run
if [ ! -f "$LOGFILE" ]; then
  echo "0" > "$LOGFILE"
fi

# Read last checkpoint
LAST_VALUE=$(tail -1 "$LOGFILE")
echo "📊 Resuming from checkpoint: $LAST_VALUE%"

# Training loop (5% increments)
CURRENT=$LAST_VALUE
while [ $CURRENT -lt 100 ]; do
  CURRENT=$((CURRENT + 5))
  echo "🔄 Training progress: $CURRENT%"
  echo "$CURRENT" >> "$LOGFILE"  # Checkpoint after each epoch
  sleep 10
done

echo "✅ Training complete: 100%"
```

**Key points:**
- Checkpoint saved **after every 5% progress** (every 10 seconds)
- If preempted at 23 seconds → last checkpoint is at 20%
- Resume reads 20%, continues from 25%
- Maximum loss: 5% of work (10 seconds)

---

## Production Checkpoint Strategies

### Frequency vs. Overhead Trade-off

| Checkpoint Frequency | Work Loss on Preempt | I/O Overhead | Best For |
|---------------------|---------------------|--------------|----------|
| Every epoch (5%) | Up to 5% | Very Low | This demo |
| Every 1% | Up to 1% | Low | Short jobs (< 1 hour) |
| Every 10 epochs | Up to 10% | Minimal | Long jobs (> 10 hours) |
| Every 5 minutes | Up to 5 min | Very Low | Wall-clock based |

**For real ML training:**
- PyTorch: `torch.save(model.state_dict(), checkpoint_path)` every N steps
- TensorFlow: `model.save()` every N steps
- Ray Train: Automatic checkpointing with `Checkpoint.from_dict()`

---

## Cleanup

```bash
# Delete both jobs
oc delete job training-checkpoint -n ml-training
oc delete job inference-preempt -n ml-inference

# Clear checkpoint file (optional - keeps PVC for next demo)
oc run checkpoint-clear --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --restart=Never -n ml-training --rm -i --tty \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "clearer",
      "image": "registry.access.redhat.com/ubi9/ubi-minimal:latest",
      "command": ["sh", "-c", "rm -f /workspace/checkpoint/training-progress.log && echo Checkpoint cleared"],
      "volumeMounts": [{
        "name": "checkpoint",
        "mountPath": "/workspace/checkpoint"
      }]
    }],
    "volumes": [{
      "name": "checkpoint",
      "persistentVolumeClaim": {"claimName": "training-checkpoint-pvc"}
    }]
  }
}' -- sh
```

---

## Key Takeaways

### Before Kueue (Manual Intervention)
```
- Production needs resources
- Admin manually kills training job
- Training loses all progress
- Training must restart from 0%
- Wasted: Hours of GPU compute
```

### After Kueue (Automated Preemption + Checkpointing)
```
- Production triggers automatic preemption
- Training checkpoints state (20% saved)
- Inference runs immediately (SLA met)
- Training resumes from 20% (no waste)
- Result: Both workloads succeed!
```

**Business Impact:**
- ✅ **Zero manual intervention** (admins sleep at night!)
- ✅ **Production SLAs guaranteed** (inference always gets resources)
- ✅ **Minimal waste** (only 10 seconds lost vs. hours)
- ✅ **95%+ utilization** (cluster always busy)
- ✅ **Developer happiness** (training eventually completes)

---

## Next Steps

Complete the module with [04-best-practices](../04-best-practices/README.md) to learn production deployment strategies!

---

## Additional Resources

- [Kueue Preemption Documentation](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/#preemption)
- [Checkpoint Patterns in ML Training](https://pytorch.org/tutorials/beginner/saving_loading_models.html)
- [Red Hat Build of Kueue - Production Best Practices](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/)
