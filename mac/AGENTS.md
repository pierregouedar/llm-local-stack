# Global rules for every session

## Never invent facts
- If a file, path, command, API, field or value that the task depends on cannot be found, STOP and say exactly what is missing and where you looked. Do not create a stand-in, do not guess its format, do not "assume a typical layout".
- STOP means: write no file, create no folder, install nothing. End your turn with the report and ask how to proceed. This applies even in autonomous or auto-approve mode.
- "Real data" means the exact file or command named in the task, or output produced by the real system right now. A fixture, sample or test file written earlier by you or by another agent is NOT real data and must not be used as a substitute.
- Never invent file paths, CLI flags, config keys, function names or library APIs. Check them first: read the file, run `--help`, read the docs or the source. If you cannot check, say it is unverified.
- Quote what you observed (command output, file content) when it drives a decision.

## Read real data before writing code that consumes it
- Before writing a parser or any code that reads a config file, a command output or an API response, open or run a REAL example first and base the code on it.
- Keep a copy of that real example as a test fixture (replace secrets such as keys, tokens and passwords with `REDACTED`).

## Tests must prove the real thing works
- Every test suite includes at least one test on a real example, not only on data you wrote yourself.
- Green tests on invented data prove nothing. Before saying a step is done, run the program itself on real input and show the result.
- When a test fails, fix the cause in the code. Never change a test just to make it pass unless the test itself is wrong, and say so.

## Work in small, verified steps
- Make a short plan first. Do one step at a time: implement, build, run, check, then move on.
- After each verified step, commit with a clear message if the project uses git.
- Keep changes focused on the task. Do not rewrite unrelated code.

## Safety
- Only create or modify files inside the current working directory (the project). Never create folders or files elsewhere.
- Never install packages or tools (pip, npm -g, cargo install, winget, brew...) without asking first; say what is needed instead.
- Never delete or overwrite files outside the project folder. Never run destructive git commands (reset --hard, push --force, clean -fd) and never push unless asked.
- Never print, log or commit secrets.

## Reporting
- End with: what you changed, how you verified it (commands + results), what is NOT verified, and anything left to do. Be honest about failures.
