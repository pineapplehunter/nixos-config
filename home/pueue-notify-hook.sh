task_id=""
command=""
result=""
exit_code=""
group=""

while (( $# > 0 )); do
  case "$1" in
    --id)
      task_id=$2
      shift 2
      ;;
    --command)
      command=$2
      shift 2
      ;;
    --result)
      result=$2
      shift 2
      ;;
    --exit-code)
      exit_code=$2
      shift 2
      ;;
    --group)
      group=$2
      shift 2
      ;;
    *)
      echo "pueue-notify-hook: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

case "$result" in
  Success) color_args=(--color '#57F287') ;;
  Failed|Errored) color_args=(--color '#ED4245') ;;
  Killed) color_args=(--color '#FEE75C') ;;
  *) color_args=() ;;
esac

if (( ${#command} > 200 )); then
  command="${command:0:200}..."
fi
# The single-quoted format intentionally keeps Markdown backticks literal.
# shellcheck disable=SC2016
printf -v content '```\n%s\n```' "$command"
if [[ -n "$exit_code" && "$exit_code" != 0 ]]; then
  printf -v content '%s\n**Exit Code:** %s' "$content" "$exit_code"
fi
if [[ -n "$group" && "$group" != default ]]; then
  printf -v content '%s\n**Group:** %s' "$content" "$group"
fi

title="Task #${task_id} ${result}"
if ! local-notify \
  --username pueue \
  --icon https://raw.githubusercontent.com/pineapplehunter/nixos-config/main/home/notification-icons/pueue.png \
  --title "$title" \
  --content "$content" \
  "${color_args[@]}"; then
  echo "pueue-notify-hook: notification delivery failed" >&2
fi
