@echo off
cd /d C:\Users\Opera\quotesdone
git commit -q -F holdout_v2_eval\containment_commit_msg.txt
echo EXIT=%errorlevel%
git rev-parse HEAD
git log --oneline -1
echo --- remaining unstaged (scratch only) ---
git status --porcelain
