@echo off
REM Pré-build : met à jour le nom de l'application depuis les paramètres
REM Usage: build_pre.bat          (local)
REM        build_pre.bat --env=prod  (production)
php %~dp0update_app_name.php %*
