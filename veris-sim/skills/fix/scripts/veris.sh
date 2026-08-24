#!/usr/bin/env sh
# veris.sh — the mechanics the veris-sim commands share, one fact per line.
# Needs sh, curl and python3. Reads VERIS_API_KEY, VERIS_API_BASE (default
# https://svc.api.veris.ai) and VERIS_ENVIRONMENT_ID from the environment;
# writes nothing outside the paths it names. Exits non-zero with the reason.
#
#   veris.sh preflight                  key · binary · docker · environment, one per line; exit 2 at the first missing
#   veris.sh env                        the environment: services, promoted world or not
#   veris.sh sandbox create [ttl-min]   creates one, waits until ready, prints id and each service's url / control_url
#   veris.sh sandbox status <id>        the same for an existing sandbox
#   veris.sh sandbox delete <id>
#   veris.sh manual <id> [service]      the service's own notes — read whole, once
#   veris.sh schema <id> [service] [table]   table names, or one table's fields and rules
#   veris.sh data <id> [service] <table> [limit]   rows, for ids and read-back
#   veris.sh token <id> [service]       the sandbox-issued access token, if the twin seeds one (oauth_tokens)
#   veris.sh fault <id> [service] <METHOD> <path> <outcome> [status] [phase] [remaining]
#                                       arms one fault row: outcome error|hang|latency; phase before|after (default after); status for error
#   veris.sh requests <id> [service] [limit]   what the sandbox received: method, path, status
set -u

base="${VERIS_API_BASE:-https://svc.api.veris.ai}"; base="${base%/}"
die() { printf 'veris: %s\n' "$*" >&2; exit "${2:-1}"; }
api() { curl -sS -m 60 -H "X-API-Key: ${VERIS_API_KEY:-}" "$@"; }
py() { python3 -c "$@"; }

need_key() { [ -n "${VERIS_API_KEY:-}" ] || die "VERIS_API_KEY is not set" 2; }
need_env() { [ -n "${VERIS_ENVIRONMENT_ID:-}" ] || die "VERIS_ENVIRONMENT_ID is not set" 2; }

# sandbox JSON → lines "service url control_url"; picks the first service when none is named
services() { # $1 sandbox json, $2 optional service name
  printf '%s' "$1" | py '
import sys,json; d=json.load(sys.stdin); want=sys.argv[1]
for s in d.get("services",[]):
    if not want or s.get("name")==want: print(s.get("name"),s.get("url"),s.get("control_url") or s.get("url"))' "${2:-}"
}
control_url() { # $1 sandbox id, $2 optional service → control_url of that service (first if unnamed)
  need_key; need_env
  sb="$(api "$base/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes/$1")" || die "sandbox $1: control plane unreachable"
  line="$(services "$sb" "${2:-}" | head -1)"
  [ -n "$line" ] || die "sandbox $1 has no service${2:+ named $2}"
  printf '%s' "$line" | awk '{print $3}'
}

cmd="${1:-}"; [ -n "$cmd" ] && shift
case "$cmd" in
preflight)
  ok() { printf 'preflight: %-12s ok%s\n' "$1" "${2:+ ($2)}"; }
  fail() { printf 'preflight: %-12s MISSING — %s\n' "$1" "$2"; exit 2; }
  [ -n "${VERIS_API_KEY:-}" ] || fail credential "VERIS_API_KEY is not set in this shell"
  ok credential
  command -v veris-proxy >/dev/null 2>&1 && veris-proxy version >/dev/null 2>&1 \
    || fail binary "veris-proxy is not on PATH; ask first, then: curl -fsSL https://raw.githubusercontent.com/veris-ai/veris-proxy/main/scripts/install.sh | sh"
  ok binary "$(veris-proxy version 2>/dev/null | head -1)"
  docker version >/dev/null 2>&1 || fail docker "no docker daemon reachable; start one"
  ok docker
  [ -n "${VERIS_ENVIRONMENT_ID:-}" ] || fail environment "VERIS_ENVIRONMENT_ID is not set; \`veris.sh env\` needs one — list with GET $base/v1/environments"
  body="$(api "$base/v1/environments/$VERIS_ENVIRONMENT_ID")" || fail environment "control plane $base unreachable"
  case "$body" in *'"id"'*) ;; *) fail environment "the control plane refused the key or does not know $VERIS_ENVIRONMENT_ID" ;; esac
  case "$body" in *'"baseline"'*'"image"'*) ok environment "$VERIS_ENVIRONMENT_ID, promoted world" ;; *) ok environment "$VERIS_ENVIRONMENT_ID, default world" ;; esac
  if [ -f .veris/setup.json ]; then
    image="$(py 'import json;print(json.load(open(".veris/setup.json")).get("image",""))')"
    dockerfile="$(py 'import json;print(json.load(open(".veris/setup.json")).get("dockerfile") or "")')"
    if [ -n "$image" ] && [ -n "$dockerfile" ]; then
      docker image inspect "$image" >/dev/null 2>&1 || fail image "$image is not built; docker build -f $dockerfile -t $image ."
      ok image "$image"
    elif [ -n "$image" ]; then ok image "$image (stock; the run pulls it)"; fi
  fi
  [ -f .veris/run.sh ] && ok run.sh ".veris/run.sh recorded" || printf 'preflight: %-12s not yet recorded\n' run.sh
  ;;
env)
  need_key; need_env
  api "$base/v1/environments/$VERIS_ENVIRONMENT_ID" | py '
import sys,json; d=json.load(sys.stdin)
print("environment", d.get("id"), d.get("name",""))
print("services", " ".join(d.get("services",[])))
b=d.get("baseline") or {}
print("world", "promoted "+(b.get("image","")[-24:]) if b.get("image") else "default (every sandbox boots the seeded world)")'
  ;;
sandbox)
  need_key; need_env
  sub="${1:-}"; [ -n "$sub" ] && shift
  case "$sub" in
  create)
    ttl="${1:-60}"
    sb="$(api -X POST -H 'Content-Type: application/json' -d "{\"ttl_minutes\":$ttl}" "$base/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes")" || die "create failed"
    id="$(printf '%s' "$sb" | py 'import sys,json;print(json.load(sys.stdin).get("id",""))')"
    [ -n "$id" ] || die "create refused: $(printf '%s' "$sb" | head -c 200)"
    i=0; while [ $i -lt 40 ]; do
      sb="$(api "$base/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes/$id")"
      st="$(printf '%s' "$sb" | py 'import sys,json;print(json.load(sys.stdin).get("status",""))')"
      case "$st" in ready) break ;; failed) die "sandbox $id failed: $(printf '%s' "$sb" | py 'import sys,json;print(json.load(sys.stdin).get("failure_reason",""))')" ;; esac
      i=$((i+1)); sleep 5
    done
    [ "$st" = ready ] || die "sandbox $id not ready after 200s ($st)"
    printf 'sandbox %s ready (ttl %s min)\n' "$id" "$ttl"; services "$sb" | awk '{print "service", $1, "url", $2, "control_url", $3}'
    ;;
  status)
    [ -n "${1:-}" ] || die "sandbox status <id>"
    sb="$(api "$base/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes/$1")" || die "unreachable"
    printf 'sandbox %s %s\n' "$1" "$(printf '%s' "$sb" | py 'import sys,json;print(json.load(sys.stdin).get("status","?"))')"
    services "$sb" | awk '{print "service", $1, "url", $2, "control_url", $3}'
    ;;
  delete)
    [ -n "${1:-}" ] || die "sandbox delete <id>"
    code="$(api -o /dev/null -w '%{http_code}' -X DELETE "$base/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes/$1")"
    case "$code" in 2*) printf 'sandbox %s deleted\n' "$1" ;; *) die "delete returned $code" ;; esac
    ;;
  *) die "sandbox create|status|delete" ;;
  esac
  ;;
manual)
  c="$(control_url "${1:?sandbox id}" "${2:-}")"
  curl -sS -m 30 "$c/veris/manual" | py 'import sys,json;print(json.load(sys.stdin).get("manual",""))'
  ;;
schema)
  c="$(control_url "${1:?sandbox id}" "${2:-}")"; table="${3:-}"
  curl -sS -m 30 "$c/veris/schema" | py '
import sys,json; d=json.load(sys.stdin); props=d.get("properties",{}); t=sys.argv[1]
if not t: print(" ".join(sorted(props))); sys.exit()
p=props.get(t);
if p is None: print("no table", t); sys.exit(1)
desc=p.get("description",""); print(t, "-", desc) if desc else print(t)
items=p.get("items",p); fields=items.get("properties",{})
for k,v in fields.items(): print(" ", k, "-", (v.get("description") or v.get("type","")))' "$table"
  ;;
data)
  c="$(control_url "${1:?sandbox id}" "${2:-}")"; table="${3:?table}"; limit="${4:-20}"
  curl -sS -m 30 "$c/veris/data?entity_type=$table&limit=$limit" | py '
import sys,json; d=json.load(sys.stdin); rows=d.get("rows",[]); print("total", d.get("total"))
for r in rows: print(json.dumps({k:(v if isinstance(v,(int,float,bool)) or v is None else str(v)[:60]) for k,v in r.items() if k!="data"}))'
  ;;
token)
  c="$(control_url "${1:?sandbox id}" "${2:-}")"
  curl -sS -m 30 "$c/veris/data?entity_type=oauth_tokens" | py '
import sys,json; d=json.load(sys.stdin); rows=[r for r in d.get("rows",[]) if r.get("status","active")=="active"]
if not rows: print("no seeded token; see the manual'"'"'s Credentials section"); sys.exit(1)
print(rows[0].get("access_token"))'
  ;;
fault)
  c="$(control_url "${1:?sandbox id}" "${2:-}")"; m="${3:?METHOD}"; path="${4:?path}"; outcome="${5:?outcome}"; status="${6:-503}"; phase="${7:-after}"; remaining="${8:-1}"
  row="$(py '
import sys,json; m,path,outcome,status,phase,remaining=sys.argv[1:7]
f={"method":m,"path":path,"outcome":outcome,"phase":phase,"remaining":int(remaining)}
if outcome=="error": f["error"]={"status":int(status),"code":str(status)}
if outcome=="latency": f["latency_ms"]=int(status); f.pop("phase",None)
print(json.dumps({"data":{"faults":[f]}}))' "$m" "$path" "$outcome" "$status" "$phase" "$remaining")"
  out="$(curl -sS -m 30 -X POST -H 'Content-Type: application/json' -d "$row" "$c/veris/data")"
  case "$out" in *'"added"'*) printf 'fault armed: %s %s %s%s phase=%s remaining=%s\n' "$m" "$path" "$outcome" "$([ "$outcome" = error ] && printf ' %s' "$status")" "$phase" "$remaining" ;; *) die "fault refused: $(printf '%s' "$out" | head -c 300)" ;; esac
  ;;
requests)
  c="$(control_url "${1:?sandbox id}" "${2:-}")"; limit="${3:-20}"
  curl -sS -m 30 "$c/veris/requests?limit=$limit" | py '
import sys,json; d=json.load(sys.stdin)
for r in d.get("requests",[]): print(r.get("ts",""), r.get("method",""), r.get("path",""), r.get("status",""), r.get("tier",""))'
  ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
