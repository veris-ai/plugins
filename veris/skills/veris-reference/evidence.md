# A short change summary

Use the repository's PR or handoff format. Include the behavior changed, the relevant
test/command and its outcome with an existing evidence reference, and any material
limitation. For example:

```markdown
Retrying a payment now reuses its operation key through the checkout handler.

Verified with <command>: <assertions/result>, against <twin/sandbox>.
Receipt or retained trace: <path/reference>.

<Only if relevant: original failure not reproduced; required case not tested;
provider/twin limitation; task premise the investigation disproved.>
```

One run may support several assertions. Link its existing receipt or retained output;
do not create another run, ledger or copy of the evidence for the description.
Omit empty sections. Use package/version metadata already available when it helps
reproduce a finding; OpenCode's `verisSkill` result includes the installed package.

Save cited redacted excerpts before sandbox cleanup, following the existing
`artifact_policy`. A trace id that disappears with the sandbox needs a saved excerpt
if it is the evidence being cited. Known contradictory behavior is a defect to resolve,
not an assumption that makes the task complete. State unverified outcomes precisely.
