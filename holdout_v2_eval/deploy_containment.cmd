@echo off
setlocal enabledelayedexpansion
cd /d C:\Users\Opera\quotesdone
set /p T=<"%USERPROFILE%\.supabase\access-token"
set SUPABASE_ACCESS_TOKEN=!T!
echo === deploying os_ops (verify_jwt ON, matching current) ===
call supabase functions deploy os_ops --project-ref htdblwldjkcgjvmqkbeh --use-api 2>&1
echo EXIT_OS_OPS=!errorlevel!
echo === deploying refunds_api (--no-verify-jwt, matching current) ===
call supabase functions deploy refunds_api --project-ref htdblwldjkcgjvmqkbeh --use-api --no-verify-jwt 2>&1
echo EXIT_REFUNDS=!errorlevel!
endlocal
