# =============================================================================
# gatekeeper-test.ps1
# OPA Gatekeeper Admission Control Testing (Windows/PowerShell)
#
# This script:
#   1. Verifies that Gatekeeper is running in the cluster
#   2. Applies ConstraintTemplates and Constraints
#   3. Tests that compliant manifests are ACCEPTED
#   4. Tests that non-compliant manifests are REJECTED
#   5. Collects evidence (cluster state snapshots)
#
# Usage (from repository root):
#   powershell -ExecutionPolicy Bypass -File scripts\gatekeeper-test.ps1
#
# Prerequisites:
#   - kubectl configured and pointing to a kind cluster
#   - Gatekeeper already installed in the cluster
# =============================================================================

$ErrorActionPreference = "Continue"

# ── Paths ────────────────────────────────────────────────────────────────────
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir       = Split-Path -Parent $ScriptDir
$TemplateDir   = Join-Path $RootDir "gatekeeper\templates"
$ConstraintDir = Join-Path $RootDir "gatekeeper\constraints"
$GoodDir       = Join-Path $RootDir "tests\good"
$BadDir        = Join-Path $RootDir "tests\bad"
$LogDir        = Join-Path $RootDir "results\logs"
$EvidenceDir   = Join-Path $RootDir "results\evidence"

foreach ($Dir in @($LogDir, $EvidenceDir)) {
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path $LogDir "gatekeeper-test-$Timestamp.log"

# ── Counters ─────────────────────────────────────────────────────────────────
$TotalTests      = 0
$PassCount       = 0
$UnexpectedCount = 0

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $LogFile -Value $Message
}

function Write-Section {
    param([string]$Title)
    Write-Log ""
    Write-Log ("=" * 70)
    Write-Log "  $Title"
    Write-Log ("=" * 70)
}

function Invoke-Kubectl {
    # Runs kubectl and returns a clean [PSCustomObject] with:
    #   .Output   - raw text (stdout + stderr merged)
    #   .ExitCode - process exit code
    #   .Lines    - string array of non-blank lines
    param([string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = "kubectl"
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $combined = ("$stdout`n$stderr").Trim()
    [PSCustomObject]@{
        Output   = $combined
        ExitCode = $proc.ExitCode
        Lines    = @($combined -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
}

function Get-ViolationMessages {
    # Extracts clean Gatekeeper [constraint-name] violation lines from kubectl output.
    param([string]$RawOutput)
    $lines = @()
    foreach ($line in ($RawOutput -split "`n")) {
        # Match "[constraint-name] message..." anywhere in the line
        if ($line -match '\[([^\]]+)\]\s+(.+)') {
            $lines += "[$($Matches[1])] $($Matches[2].Trim())"
        }
    }
    $lines
}

# =============================================================================
#  STEP 1 - Verify Gatekeeper is running
# =============================================================================

Write-Section "STEP 1: Verify Gatekeeper is running"

$result = Invoke-Kubectl "get pods -n gatekeeper-system --no-headers"
if ($result.ExitCode -ne 0 -or $result.Lines.Count -eq 0) {
    Write-Log "  ERROR: Gatekeeper does not appear to be installed."
    Write-Log "  Install it with:"
    Write-Log "    kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.18.0/deploy/gatekeeper.yaml"
    exit 1
}
foreach ($line in $result.Lines) { Write-Log "  $line" }
Write-Log ""
Write-Log "  Gatekeeper is running."

# =============================================================================
#  STEP 2 - Apply ConstraintTemplates
# =============================================================================

Write-Section "STEP 2: Apply ConstraintTemplates"

$Templates = Get-ChildItem -Path $TemplateDir -Filter "*.yaml" -File
foreach ($File in $Templates) {
    Write-Log "  Applying: $($File.Name)"
    $r = Invoke-Kubectl "apply -f `"$($File.FullName)`""
    Write-Log "    $($r.Output)"
}

Write-Log ""
Write-Log "  Waiting for CRDs to be established..."

$CRDNames = @("k8snoroot", "k8snoprivescalation", "k8snolatesttag")
foreach ($crd in $CRDNames) {
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $r = Invoke-Kubectl "get constrainttemplate $crd -o jsonpath={.status.created}"
        if ($r.Output -eq "true" -or $r.Output -eq "True") {
            Write-Log "    $crd - READY"
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        Write-Log "    $crd - TIMEOUT (not ready after 60 s)"
    }
}

# =============================================================================
#  STEP 3 - Apply Constraints
# =============================================================================

Write-Section "STEP 3: Apply Constraints"

$Constraints = Get-ChildItem -Path $ConstraintDir -Filter "*.yaml" -File
foreach ($File in $Constraints) {
    Write-Log "  Applying: $($File.Name)"
    $r = Invoke-Kubectl "apply -f `"$($File.FullName)`""
    Write-Log "    $($r.Output)"
}

Write-Log ""
Write-Log "  Waiting 10 seconds for constraints to sync..."
Start-Sleep -Seconds 10

# =============================================================================
#  STEP 4 - Test GOOD manifest (should be ACCEPTED)
# =============================================================================

Write-Section "STEP 4: Test GOOD manifest (expect ACCEPTED)"

$GoodFile = Join-Path $GoodDir "deployment-good.yaml"
$TotalTests++

Write-Log "  File: tests/good/deployment-good.yaml"
$r = Invoke-Kubectl "apply --dry-run=server -f `"$GoodFile`""

if ($r.ExitCode -eq 0) {
    Write-Log "  >> ACCEPTED (as expected)"
    $PassCount++
} else {
    Write-Log "  >> UNEXPECTED REJECTION"
    foreach ($v in (Get-ViolationMessages $r.Output)) { Write-Log "     $v" }
    $UnexpectedCount++
}

# =============================================================================
#  STEP 5 - Test BAD manifests (should be REJECTED)
# =============================================================================

Write-Section "STEP 5: Test BAD manifests (expect REJECTED)"

$BadFiles = @(
    "deployment-root.yaml",
    "deployment-priv-escalation.yaml",
    "deployment-latest-tag.yaml",
    "deployment-multi-violation.yaml"
)

foreach ($FileName in $BadFiles) {
    $FilePath = Join-Path $BadDir $FileName
    $TotalTests++

    Write-Log ""
    Write-Log "  File: tests/bad/$FileName"
    $r = Invoke-Kubectl "apply --dry-run=server -f `"$FilePath`""

    if ($r.ExitCode -ne 0) {
        $violations = Get-ViolationMessages $r.Output
        if ($violations.Count -gt 0) {
            foreach ($v in $violations) { Write-Log "    $v" }
        } else {
            Write-Log "    (rejected - no parseable violation line)"
        }
        Write-Log "  >> REJECTED (as expected)"
        $PassCount++
    } else {
        Write-Log "  >> UNEXPECTED ACCEPT - bad manifest was not blocked!"
        $UnexpectedCount++
    }
}

# =============================================================================
#  STEP 6 - Collect evidence snapshots
# =============================================================================

Write-Section "STEP 6: Collect evidence"

$evidenceFiles = @{
    "constrainttemplates.yaml" = "get constrainttemplates -o yaml"
    "constraints.yaml"         = "get k8snoroot,k8snoprivescalation,k8snolatesttag -o yaml"
    "gatekeeper-pods.txt"      = "get pods -n gatekeeper-system -o wide"
}

foreach ($name in $evidenceFiles.Keys) {
    $outPath = Join-Path $EvidenceDir $name
    $r = Invoke-Kubectl $evidenceFiles[$name]
    Set-Content -Path $outPath -Value $r.Output -Encoding UTF8
    Write-Log "  Saved: results/evidence/$name"
}

# =============================================================================
#  SUMMARY
# =============================================================================

Write-Section "SUMMARY"

Write-Log ""
Write-Log "  Total tests        : $TotalTests"
Write-Log "  Expected results   : $PassCount"
Write-Log "  Unexpected results : $UnexpectedCount"
Write-Log ""
Write-Log "  Log:      $LogFile"
Write-Log "  Evidence: $EvidenceDir"
Write-Log ""

if ($UnexpectedCount -eq 0) {
    Write-Log "  >>> ALL GATEKEEPER TESTS PASSED <<<"
    exit 0
} else {
    Write-Log "  >>> WARNING: $UnexpectedCount test(s) produced unexpected results <<<"
    exit 1
}
