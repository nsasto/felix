$ErrorActionPreference = 'Stop'

felix spec status s-0000 planned
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

felix run s-0000 --sync --no-backpressure -Verbose
exit $LASTEXITCODE
