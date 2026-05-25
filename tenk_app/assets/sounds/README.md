# 사운드 자산

녹화·UI 효과음을 두는 곳. `audioplayers` 가 `AssetSource('sounds/<file>')` 형태로 참조.

## record_start.wav

녹화가 실제로 시작되는 순간 1회 재생. 종소리 같은 chime — fundamental 1000Hz +
하모닉 1500/2200Hz, 도입부 4ms attack + exponential decay(τ≈90ms), 첫 30ms 동안
~5% pitch chirp 으로 "당-" 도입감. 22050Hz / 16bit mono, 280ms, ~12KB.

처음엔 1200Hz 순수 sine wave 였는데 "기계음 같다" 는 피드백 받아 종소리 envelope +
하모닉 mixing 으로 교체.

**재생성**: 같은 PowerShell 한 블록을 다시 돌리면 됨. tone/duration 등 파라미터는
$f1/$f2/$f3 와 $ms, decay rate 등으로 조절. 짧고 부드러운 효과음을 원하면 $ms 줄이고
decay rate(`-$t * 11` 의 11) 올리면 됨.

```powershell
$out = "tenk_app\assets\sounds\record_start.wav"
$sampleRate = 22050; $ms = 280
$f1 = 1000.0; $f2 = 1500.0; $f3 = 2200.0
$n = [int]($sampleRate * $ms / 1000)
$s = [System.IO.File]::Create($out); $w = New-Object System.IO.BinaryWriter $s
try {
  $w.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
  $w.Write([uint32]($n*2 + 36))
  $w.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))
  $w.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
  $w.Write([uint32]16); $w.Write([uint16]1); $w.Write([uint16]1)
  $w.Write([uint32]$sampleRate); $w.Write([uint32]($sampleRate*2))
  $w.Write([uint16]2); $w.Write([uint16]16)
  $w.Write([System.Text.Encoding]::ASCII.GetBytes("data")); $w.Write([uint32]($n*2))
  for ($i=0;$i -lt $n;$i++) {
    $t = [double]$i/$sampleRate
    $env = (1 - [Math]::Exp(-$t*250)) * [Math]::Exp(-$t*11)
    $pm = 1 + 0.05 * [Math]::Exp(-$t*35)
    $sig = 0.6*[Math]::Sin(2*[Math]::PI*$f1*$pm*$t) + 0.3*[Math]::Sin(2*[Math]::PI*$f2*$pm*$t) + 0.15*[Math]::Sin(2*[Math]::PI*$f3*$pm*$t)
    $v = $env * $sig * 0.5
    if ($v -gt 1) { $v = 1 } elseif ($v -lt -1) { $v = -1 }
    $w.Write([int16][int]($v*32767))
  }
} finally { $w.Dispose(); $s.Dispose() }
```

royalty-free 다른 효과음(mp3/wav) 으로 교체하고 싶으면 같은 파일명으로 덮어쓰면 됨.
Flutter 는 자산 변경 시 hot reload 안 됨 — 앱 stop 후 `flutter run` 으로 재시작 필요.
