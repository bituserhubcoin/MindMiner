<#
MindMiner  Copyright (C) 2018-2020  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

if ([Config]::ActiveTypes -notcontains [eMinerType]::nVidia -and [Config]::ActiveTypes -notcontains [eMinerType]::AMD) { exit }
if (![Config]::Is64Bit) { exit }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$Cfg = ReadOrCreateMinerConfig "Do you want use to mine the '$Name' miner" ([IO.Path]::Combine($PSScriptRoot, $Name + [BaseConfig]::Filename)) @{
	Enabled = $true
	BenchmarkSeconds = 90
	ExtraArgs = $null
	Algorithms = @(
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "aeternity" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "bbc" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "beamhash" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "beamhashII" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "blake2s" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "bfc" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "cortex" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "cuckaroo29" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "cuckarood29" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "cuckarood29v" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cuckaroom29" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "cuckatoo31" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "eaglesong" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "equihash125_4" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "equihash144_5" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "equihash192_7" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "equihashZCL" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "equihash96_5" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "ethash" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "grimm" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "swap" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "vds" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "zhash" }
)}

if (!$Cfg.Enabled) { return }

$AMD = @("aeternity", "beamhash", "beamhashII", "blake2s", "bfc", "eaglesong", "equihash125_4", "equihash144_5", "equihash192_7", "equihashZCL", "swap")

$Cfg.Algorithms | ForEach-Object {
	if ($_.Enabled) {
		$Algo = Get-Algo($_.Algorithm)
		if ($Algo) {
			# find pool by algorithm
			$Pool = Get-Pool($Algo)
			if ($Pool) {
				if ($_.Algorithm -match "zhash") { $_.Algorithm = "equihash144_5" }
				$types = if ([Config]::ActiveTypes -contains [eMinerType]::nVidia) { [eMinerType]::nVidia } else { $null }
				if ($AMD -contains $_.Algorithm) {
					if ([Config]::ActiveTypes -contains [eMinerType]::nVidia -and [Config]::ActiveTypes -contains [eMinerType]::AMD) {
						$types = @([eMinerType]::nVidia, [eMinerType]::AMD)
					}
					elseif ([Config]::ActiveTypes -contains [eMinerType]::AMD) {
						$types = [eMinerType]::AMD
					}
				}
				$extrargs = Get-Join " " @($Cfg.ExtraArgs, $_.ExtraArgs)
				$alg = "-a $($_.Algorithm)"
				if ($_.Algorithm -match "equihash" -and $extrargs -notmatch "-pers") {
					$alg = Get-Join " " @($alg, "--pers auto")
				}
				if ($_.Algorithm -match "equihashZCL") {
					$alg = "-a equihash192_7 --pers ZcashPoW"
				}
				if ($_.Algorithm -match "ethash" -and ($Pool.Name -match "nicehash" -or $Pool.Name -match "mph")) {
					$alg = Get-Join " " @($alg, "--proto stratum")
				}
				$fee = if ($_.Algorithm -match "cortex") { 5 } elseif ($_.Algorithm -match "bfc") { 3 }
					elseif ($_.Algorithm -match "cuckaroom29") { 3 } elseif ($_.Algorithm -match "cuckarood29v") { 10 }
					elseif ($_.Algorithm -match "ethash") { 0.65 } else { 2 }
				$benchsecs = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
				$runbefore = $_.RunBefore
				$runafter = $_.RunAfter
				$user = $Pool.User
				if ($user -notmatch ".$([Config]::WorkerNamePlaceholder)" -and !$user.Contains(".")) {
					$user = "$user._"
				}
				$nvml = if ($extrargs -match "--nvml") { [string]::Empty } else { "--nvml 0 " }
				$hosts = [string]::Empty
				$Pool.Hosts | ForEach-Object { $hosts = Get-Join " " @($hosts, "-s $_`:$($Pool.PortUnsecure) -u $user -p $($Pool.Password)") }
				$types | ForEach-Object {
					if ($_) {
						$devs = if ($_ -eq [eMinerType]::nVidia) { "--cuda 1 $nvml--opencl 0" } else { "--cuda 0 --opencl 1" }
						$port = if ($_ -eq [eMinerType]::nVidia) { 42000 } else { 42001 }
						[MinerInfo]@{
							Pool = $Pool.PoolName()
							PoolKey = $Pool.PoolKey()
							Priority = $Pool.Priority
							Name = $Name
							Algorithm = $Algo
							Type = $_
							TypeInKey = $true
							API = "gminer"
							URI = "https://github.com/develsoftware/GMinerRelease/releases/download/1.95/gminer_1_95_windows64.zip"
							Path = "$Name\miner.exe"
							ExtraArgs = $extrargs
							Arguments = "$alg $hosts --api $port --pec 0 -w 0 $devs $extrargs"
							Port = $port
							BenchmarkSeconds = $benchsecs
							RunBefore = $runbefore
							RunAfter = $runafter
							Fee = $fee
						}
					}
				}
			}
		}
	}
}