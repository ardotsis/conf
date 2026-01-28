echo "conf profile: vultr"

sudo_flag="$HOME/.sudo_as_admin_successful"
if [[ -e "$sudo_flag" ]]; then
	rm -f "$sudo_flag"
fi
