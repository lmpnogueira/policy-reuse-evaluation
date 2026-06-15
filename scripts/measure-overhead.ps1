# =============================================================================
# measure-overhead.ps1
# Lightweight Overhead Measurement for Policy-as-Code Enforcement
#
# Measures execution time for four operations, each repeated N times:
#   M1 - CI validation WITHOUT Conftest (kubectl --dry-run=client only)
#   M2 - CI validation WITH Conftest (conftest test)
#   M3 - Admission control: allowed manifest (kubectl --dry-run=server)
#   M4 - Admission control: rejected manifest (kubectl --dry-run=server)
#
# Usage (from repository root):
#   powershell -ExecutionPolicy Bypass -File scripts\measure-overhead.ps1
#
# Prerequisites:
#   - conftest installed and available in PATH
#   - kubectl installed and configured (kind cluster running for M3/M4)
#   - Gatekeeper installed with constraints applied (for M3/M4)
# =============================================================================

param(
    [int]$Iterations = 20
)

# ── Configuration ────────────────────────────────────────────────────────────

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir    = Split-Path -Parent $ScriptDir
$PolicyDir  = Join-Path $RootDir "policies\kubernetes"
$GoodDir    = Join-Path $RootDir "tests\good"
$BadDir     = Join-Path $RootDir "tests\bad"
$ResultsDir = Join-Path $RootDir "results\measurements"

$GoodManifest = Join-Path $RootDir "tests\good\deployment-good.yaml"
$BadManifest  = Join-Path $RootDir "tests\bad\deployment-root.yaml"

if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$CsvFile   = Join-Path $ResultsDir "overhead-$Timestamp.csv"
$LogFile   = Join-Path $ResultsDir "overhead-$Timestamp.log"

# ── Helper functions ─────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $LogFile -Value $Message
}

function Measure-Operation {
    param(
        [string]$Id,
        [string]$Name,
        [scriptblock]$Operation,
        [int]$Runs
    )

    Write-Log ""
    Write-Log "=== $Id - $Name ($Runs iterations) ==="

    $timings = @()

    for ($i = 1; $i -le $Runs; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & $Operation 2>&1 | Out-Null
        } catch {
            # Some operations (e.g. conftest on bad manifests) exit non-zero;
            # this is expected and should not stop the measurement.
        }
        $sw.Stop()
        $ms = $sw.Elapsed.TotalMilliseconds
        $timings += $ms
        Write-Log ("  Run {0}: {1:N1} ms" -f $i, $ms)
    }

    # Discard first run (warm-up) if more than 1 iteration
    if ($Runs -gt 1) {
        $statsTimings = $timings[1..($Runs - 1)]
        Write-Log "  (first run discarded as warm-up; statistics over $($statsTimings.Count) runs)"
    } else {
        $statsTimings = $timings
    }

    $avg = ($statsTimings | Measure-Object -Average).Average
    $min = ($statsTimings | Measure-Object -Minimum).Minimum
    $max = ($statsTimings | Measure-Object -Maximum).Maximum

    # Standard deviation
    $sumSqDiff = 0
    foreach ($t in $statsTimings) { $sumSqDiff += ($t - $avg) * ($t - $avg) }
    $sd = [math]::Sqrt($sumSqDiff / $statsTimings.Count)

    Write-Log ("  --> Avg: {0:N1} ms | Min: {1:N1} ms | Max: {2:N1} ms | SD: {3:N1} ms" -f $avg, $min, $max, $sd)

    # Return result object
    return [PSCustomObject]@{
        Id         = $Id
        Operation  = $Name
        Iterations = $statsTimings.Count
        AvgMs      = [math]::Round($avg, 1)
        MinMs      = [math]::Round($min, 1)
        MaxMs      = [math]::Round($max, 1)
        SdMs       = [math]::Round($sd, 1)
        AllMs      = ($statsTimings | ForEach-Object { [math]::Round($_, 1) }) -join ";"
    }
}

# ── Measurements ─────────────────────────────────────────────────────────────

Write-Log "Overhead Measurement - $Timestamp"
Write-Log "Iterations per operation: $Iterations"
Write-Log "Good manifest: $GoodManifest"
Write-Log "Bad manifest:  $BadManifest"
Write-Log "Policy dir:    $PolicyDir"

$results = @()

# M1 - Baseline: kubectl dry-run client only (no policy engine)
$results += Measure-Operation -Id "M1" -Name "kubectl --dry-run=client (no policy)" -Runs $Iterations -Operation {
    kubectl apply --dry-run=client -f $GoodManifest
}

# M2 - CI validation: conftest test on all manifests
$results += Measure-Operation -Id "M2" -Name "conftest test (all manifests)" -Runs $Iterations -Operation {
    conftest test $GoodDir $BadDir -p $PolicyDir --all-namespaces --no-color
}

# M3/M4 - Admission control (require a running cluster with Gatekeeper)
$clusterAvailable = $false
try {
    $check = kubectl cluster-info 2>&1 | Out-String
    if ($check -match "Kubernetes.*is running") {
        $clusterAvailable = $true
    }
} catch { }

if ($clusterAvailable) {
    Write-Log ""
    Write-Log "Cluster detected - running admission measurements (M3, M4)"

    # M3 - Admission: allowed manifest via dry-run=server
    $results += Measure-Operation -Id "M3" -Name "kubectl --dry-run=server (allowed)" -Runs $Iterations -Operation {
        kubectl apply --dry-run=server -f $GoodManifest
    }

    # M4 - Admission: rejected manifest via dry-run=server
    $results += Measure-Operation -Id "M4" -Name "kubectl --dry-run=server (rejected)" -Runs $Iterations -Operation {
        kubectl apply --dry-run=server -f $BadManifest
    }
} else {
    Write-Log ""
    Write-Log "WARNING: No Kubernetes cluster detected - skipping M3/M4 (admission measurements)"
    Write-Log "         Start Docker and kind cluster, then re-run to collect M3/M4 data."
}

# ── Write CSV ────────────────────────────────────────────────────────────────

$results | Select-Object Id, Operation, Iterations, AvgMs, MinMs, MaxMs, SdMs, AllMs |
    Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8

Write-Log ""
Write-Log "=== Summary ==="
Write-Log ""
Write-Log ("{0,-4} {1,-45} {2,10} {3,10} {4,10} {5,10}" -f "ID", "Operation", "Avg (ms)", "Min (ms)", "Max (ms)", "SD (ms)")
Write-Log ("{0,-4} {1,-45} {2,10} {3,10} {4,10} {5,10}" -f "--", ("-" * 45), "--------", "--------", "--------", "-------")
foreach ($r in $results) {
    Write-Log ("{0,-4} {1,-45} {2,10:N1} {3,10:N1} {4,10:N1} {5,10:N1}" -f $r.Id, $r.Operation, $r.AvgMs, $r.MinMs, $r.MaxMs, $r.SdMs)
}

Write-Log ""
Write-Log "CSV saved to: $CsvFile"
Write-Log "Log saved to: $LogFile"
Write-Log ""

# ── Overhead calculation ─────────────────────────────────────────────────────

$m1 = $results | Where-Object { $_.Id -eq "M1" }
$m2 = $results | Where-Object { $_.Id -eq "M2" }

if ($m1 -and $m2 -and $m1.AvgMs -gt 0) {
    $overheadMs = $m2.AvgMs - $m1.AvgMs
    Write-Log ("Conftest overhead vs. baseline: {0:N1} ms ({1:N1}x)" -f $overheadMs, ($m2.AvgMs / $m1.AvgMs))
}

$m3 = $results | Where-Object { $_.Id -eq "M3" }
$m4 = $results | Where-Object { $_.Id -eq "M4" }

if ($m3 -and $m4 -and $m3.AvgMs -gt 0) {
    $admissionDelta = $m4.AvgMs - $m3.AvgMs
    Write-Log ("Admission rejection delta vs. allowed: {0:N1} ms" -f $admissionDelta)
}

Write-Log ""
Write-Log "Done."
