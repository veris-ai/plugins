#!/bin/sh
# Four imperatives whose absence loses a graded outcome, delivered on the turn
# rather than from a file the agent may or may not consult.
#
# An instruction inside a reference carries less force than the same words in
# the task. The measured spread is not small: the same directive moved the
# behaviour 3 of 3 times from the prompt, 2 of 6 from a hook, and 0 of 4 from
# skill prose that was demonstrably read in 4 of those 6 runs. So these four
# sentences live here and in the prompt line the README gives the engineer, and
# the skills keep the procedure.
#
# Conditional on a twin being in play, because this fires on every prompt of
# every session. Kept short for the same reason.
cat >/dev/null   # the hook payload on stdin is not read; nothing here depends on it

cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"When this task involves a service with a Veris twin available:\n- If it names a failure, make that failure happen against the twin and drive the current code through it before the design is fixed.\n- Drive the default path: the call the task names, made by a caller you did not change, twice, through the changed code; count what the twin stored. A guard that does not engage there is not done.\n- Claim no red and no green without the receipt of the run that produced it, read after the run.\n- Every premise the task states that you measured false is its own line in the change description, and is never restated as fact."}}
EOF
