setlocal

for /d %%D in ("%~dp0*") do (
    if /I not "%%~nxD"=="common" (
        if exist "%%~fD\run.cmd" (
            echo.
            echo ========================================
            echo Running: %%~nxD
            echo ========================================

            pushd "%%~fD"
            call run.cmd
            popd
        )
    )
)

echo.
echo All scripts completed.
pause