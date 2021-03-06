<#
MindMiner  Copyright (C) 2018-2020  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

if ([Config]::ActiveTypes -notcontains [eMinerType]::nVidia -and [Config]::ActiveTypes -notcontains [eMinerType]::AMD) { exit }
if (![Config]::Is64Bit) { exit }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$Cfg = [BaseConfig]::ReadOrCreate([IO.Path]::Combine($PSScriptRoot, $Name + [BaseConfig]::Filename), @{
	Enabled = $true
	BenchmarkSeconds = 120
	ExtraArgs = $null
	Algorithms = @(
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "aion" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "beam" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "beamv2" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cuckatoo31" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cuckatoo32" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cuckarood29" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cuckaroom29" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "equihash125" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "equihash144" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "equihash192" }
		[AlgoInfoEx]@{ Enabled = $([Config]::ActiveTypes -notcontains [eMinerType]::nVidia); Algorithm = "equihash96" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "equihashBTG" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "equihashZCL" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "zhash" }
)})

if (!$Cfg.Enabled) { return }

$url = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/0.98/lolMiner_v098_Win64.zip"

$Cfg.Algorithms | ForEach-Object {
	if ($_.Enabled) {
		$Algo = Get-Algo($_.Algorithm)
		if ($Algo) {
			# find pool by algorithm
			$Pool = Get-Pool($Algo)
			if ($Pool) {
				$extrargs = Get-Join " " @($Cfg.ExtraArgs, $_.ExtraArgs)
				$coin = [string]::Empty
				$fee = 1
				if ($extrargs -notmatch "--coin ") {
					switch ($_.Algorithm) {
						"aion" { $coin = "--coin AION" }
						"beam" { $coin = "--coin BEAM" }
						"beamv2" { $coin = "--coin BEAM-II" }
						"cuckatoo31" { $coin = "--coin GRIN-C31"; $fee = 2 }
						"cuckatoo32" { $coin = "--coin GRIN-C32"; $fee = 2 }
						"cuckarood29" { $coin = "--coin MWC-C29D"; $fee = 2 }
						"cuckaroom29" { $coin = "--coin GRIN-C29M"; $fee = 2 }
						"zhash" { $coin = "--coin AUTO144_5" }
						"equihash125" { $coin = "--coin ZEL" }
						"equihash144" { $coin = "--coin AUTO144_5" }
						"equihash192" { $coin = "--coin AUTO192_7" }
						"equihash96" { $coin = "--coin MNX" }
						"equihashBTG" { $coin = "--coin BTG" }
						"equihashZCL" { $coin = "--coin AUTO192_7 --overwritePersonal ZcashPoW" }
					}
				}
				$pools = "--pool $($Pool.Hosts -join ";") --port $(($Pool.Hosts | ForEach-Object { $Pool.PortUnsecure }) -join ";") --user $(($Pool.Hosts | ForEach-Object { $Pool.User }) -join ";") --pass $(($Pool.Hosts | ForEach-Object { $Pool.Password }) -join ";") --tls $(($Pool.Hosts | ForEach-Object { 0 }) -join ";")"
				[MinerInfo]@{
					Pool = $Pool.PoolName()
					PoolKey = $Pool.PoolKey()
					Priority = $Pool.Priority
					Name = $Name
					Algorithm = $Algo
					Type = [eMinerType]::nVidia
					TypeInKey = $true
					API = "lolnew"
					URI = $url
					Path = "$Name\lolMiner.exe"
					ExtraArgs = $extrargs
					Arguments = "$coin $pools --apiport 4068 --timeprint 1 --disable_memcheck 1 --devices NVIDIA $extrargs"
					Port = 4068
					BenchmarkSeconds = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
					RunBefore = $_.RunBefore
					RunAfter = $_.RunAfter
					Fee = $fee
				}
				[MinerInfo]@{
					Pool = $Pool.PoolName()
					PoolKey = $Pool.PoolKey()
					Priority = $Pool.Priority
					Name = $Name
					Algorithm = $Algo
					Type = [eMinerType]::AMD
					TypeInKey = $true
					API = "lolnew"
					URI = $url
					Path = "$Name\lolMiner.exe"
					ExtraArgs = $extrargs
					Arguments = "$coin $pools --apiport 4028 --timeprint 1 --disable_memcheck 1 --devices AMD $extrargs"
					Port = 4028
					BenchmarkSeconds = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
					RunBefore = $_.RunBefore
					RunAfter = $_.RunAfter
					Fee = $fee
				}
			}
		}
	}
}