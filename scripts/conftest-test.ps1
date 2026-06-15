# =============================================================================
# conftest-test.ps1
# Policy-as-Code Validation with Conftest (Windows/PowerShell)
#
# Runs Conftest against all Kubernetes manifests in tests/good/ and tests/bad/
# to verify that OPA/Rego policies correctly PASS compliant manifests and
# FAIL non-compliant ones.
#
# Usage (from repository root):
#   powershell -ExecutionPolicy Bypass -File scripts\conftest-test.ps1
#
# Prerequisites:
#   - conftest installed and available in PATH
# =============================================================================

# ── Configuration ────────────────────────────────────────────────────────────
# Resolve paths relative to the repository root (one level above scripts/).

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir    = Split-Path -Parent $ScriptDir
$PolicyDir  = Join-Path $RootDir "policies\kubernetes"
$GoodDir    = Join-Path $RootDir "tests\good"
$BadDir     = Join-Path $RootDir "tests\bad"
$ResultsDir = Join-Path $RootDir "results\logs"

# Ensure the results directory exists.
if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
}

# Log file with timestamp so each run is preserved.
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path $ResultsDir "conftest-test-$Timestamp.log"

# ── Counters ─────────────────────────────────────────────────────────────────
# Track pass/fail results for the final summary.

$TotalTests      = 0
$PassCount        = 0
$FailCount        = 0
$UnexpectedCount  = 0   # good manifest that failed, or bad manifest that passed

# ── Helper: write to both console and log file ──────────────────────────────

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $LogFile -Value $Message
}

# ── Helper: run conftest on a single file ────────────────────────────────────
# Parameters:
#   $FilePath      – absolute path to the YAML manifest
#   $ShouldPass    – $true if the manifest is expected to pass all policies
#   $Label         – display label (GOOD or BAD)

function Test-Manifest {
    param(
        [string]$FilePath,
        [bool]$ShouldPass,
        [string]$Label
    )

    $script:TotalTests++
    $RelPath = $FilePath.Replace($RootDir + "\", "")

    Write-Log ""
    Write-Log ("=" * 70)
    Write-Log "[$Label] $RelPath"
    Write-Log ("-" * 70)

    # Run conftest and capture both stdout and stderr.
    $Output = & conftest test $FilePath --policy $PolicyDir 2>&1 | Out-String
    $ExitCode = $LASTEXITCODE

    # Print the raw conftest output for full traceability.
    Write-Log $Output.TrimEnd()

    # ── Evaluate the result against expectations ─────────────────────────
    if ($ShouldPass) {
        # GOOD manifest: conftest should exit 0 (no violations).
        if ($ExitCode -eq 0) {
            Write-Log ">> RESULT: PASS (as expected)"
            $script:PassCount++
        }
        else {
            Write-Log ">> RESULT: UNEXPECTED FAIL - good manifest produced violations!"
            $script:UnexpectedCount++
        }
    }
    else {
        # BAD manifest: conftest should exit non-zero (violations found).
        if ($ExitCode -ne 0) {
            Write-Log ">> RESULT: FAIL (as expected - policy violations detected)"
            $script:PassCount++
        }
        else {
            Write-Log ">> RESULT: UNEXPECTED PASS - bad manifest was not caught!"
            $script:UnexpectedCount++
        }
    }
}

# ── Helper: count violation lines in conftest output ─────────────────────────
# Used specifically for the multi-violation manifest to verify multiple errors.

function Get-ViolationCount {
    param([string]$FilePath)

    # Use --no-color to strip ANSI escape codes from output for reliable parsing.
    $RawOutput = & conftest test $FilePath --policy $PolicyDir --no-color 2>&1
    $Count = 0
    foreach ($item in $RawOutput) {
        $line = "$item"
        if ($line -match "FAIL\s+-") {
            $Count++
        }
    }
    return $Count
}

# =============================================================================
#  SECTION 1 — Test GOOD manifests (expected: PASS all policies)
# =============================================================================

Write-Log "###################################################################"
Write-Log "#  SECTION 1: GOOD MANIFESTS (should PASS all policies)          #"
Write-Log "###################################################################"

$GoodFiles = Get-ChildItem -Path $GoodDir -Filter "*.yaml" -File
foreach ($File in $GoodFiles) {
    Test-Manifest -FilePath $File.FullName -ShouldPass $true -Label "GOOD"
}

# =============================================================================
#  SECTION 2 — Test BAD manifests (expected: FAIL with violations)
# =============================================================================

Write-Log ""
Write-Log "###################################################################"
Write-Log "#  SECTION 2: BAD MANIFESTS (should FAIL with violations)        #"
Write-Log "###################################################################"

$BadFiles = Get-ChildItem -Path $BadDir -Filter "*.yaml" -File
foreach ($File in $BadFiles) {
    Test-Manifest -FilePath $File.FullName -ShouldPass $false -Label "BAD"
}

# =============================================================================
#  SECTION 3 — Multi-violation check
#  The multi-violation manifest should trigger at least 5 distinct violations
#  (one per policy: P1 root, P2 escalation, P3 resources x4, P4 latest, P5 privileged).
# =============================================================================

Write-Log ""
Write-Log "###################################################################"
Write-Log "#  SECTION 3: MULTI-VIOLATION DEEP CHECK                         #"
Write-Log "###################################################################"

$MultiFile = Join-Path $BadDir "deployment-multi-violation.yaml"

if (Test-Path $MultiFile) {
    $ViolationCount = Get-ViolationCount -FilePath $MultiFile
    $script:TotalTests++

    Write-Log ""
    Write-Log "File: deployment-multi-violation.yaml"
    Write-Log "Violations found: $ViolationCount"

    # Expect at least 5 violations:
    #   P1 (runAsNonRoot)           = 1
    #   P2 (allowPrivilegeEscalation) = 1
    #   P3 (cpu/mem requests+limits)  = 4
    #   P4 (latest tag)             = 1
    #   P5 (privileged)             = 1
    #   Total minimum               = 8
    $MinExpected = 5

    if ($ViolationCount -ge $MinExpected) {
        Write-Log ">> RESULT: PASS - $ViolationCount violations detected (minimum expected: $MinExpected)"
        $script:PassCount++
    }
    else {
        Write-Log ">> RESULT: UNEXPECTED - only $ViolationCount violations (expected at least $MinExpected)"
        $script:UnexpectedCount++
    }
}
else {
    Write-Log ">> SKIP: deployment-multi-violation.yaml not found"
}

# =============================================================================
#  SUMMARY
# =============================================================================

Write-Log ""
Write-Log "###################################################################"
Write-Log "#  SUMMARY                                                       #"
Write-Log "###################################################################"
Write-Log ""
Write-Log "Total tests run      : $TotalTests"
Write-Log "Expected results     : $PassCount"
Write-Log "Unexpected results   : $UnexpectedCount"
Write-Log ""
Write-Log "Log saved to: $LogFile"
Write-Log ""

if ($UnexpectedCount -eq 0) {
    Write-Log ">>> ALL TESTS BEHAVED AS EXPECTED <<<"
    exit 0
}
else {
    Write-Log ">>> WARNING: $UnexpectedCount test(s) produced unexpected results <<<"
    exit 1
}
