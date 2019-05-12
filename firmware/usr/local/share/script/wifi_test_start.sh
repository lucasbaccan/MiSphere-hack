#!/bin/sh

if [ "${1}" == "fast" ]; then
	if [ -e /sys/module/bcmdhd ]; then
		wl up
	fi

	/tmp/wifi_start.sh && exit 0
fi

#Do not save conf to SD card
SYNC_CONIG ()
{
	if [ -e /tmp/wifi.conf ]; then
		echo "==> Load wifi.conf from /tmp ..."
		wificonf=`cat /tmp/wifi.conf | sed -e 's/\r$//'`
		echo "${wificonf}" > /pref/wifi.conf
	elif [ ! -e /pref/wifi.conf ]; then
		cp /usr/local/share/script/wifi.conf /pref/wifi.conf
	fi
}

wait_mmc_add ()
{
	if [ "${WIFI_EN_STATUS}" == "" ]; then
		WIFI_EN_STATUS=1
	fi
	/usr/local/share/script/t_gpio.sh ${WIFI_EN_GPIO} $(($(($WIFI_EN_STATUS + 1)) % 2))
	/usr/local/share/script/t_gpio.sh ${WIFI_EN_GPIO} ${WIFI_EN_STATUS}
	if [ -e /proc/ambarella/mmc_fixed_cd ]; then
		mmci=`grep mmc /proc/ambarella/mmc_fixed_cd |awk $'{print $1}'|cut -c 4|tail -n 1`
		echo "${mmci} 1" > /proc/ambarella/mmc_fixed_cd
	else
		echo 1 > /sys/module/ambarella_config/parameters/sd1_slot0_fixed_cd
	fi

	n=0
	while [ -z "`ls /sys/bus/sdio/devices`" ] && [ $n -ne 30 ]; do
		n=$(($n + 1))
		sleep 0.1
	done
}

wait_wlan0 ()
{
	n=0
	ifconfig wlan0
	waitagain=$?
	while [ $waitagain -ne 0 ] && [ $n -ne 30 ]; do
		n=$(($n + 1))
		sleep 0.1
		ifconfig wlan0
		waitagain=$?
	done
}

SYNC_CONIG

conf=`cat /pref/wifi.conf | grep -Ev "^#"`
export `echo "${conf}"|grep -v PASSW|grep -v SSID|grep -vI $'^\xEF\xBB\xBF'`
export PASSWORD=`echo "${conf}" | grep PASSWORD | cut -c 10-`
export AP_PASSWD=`echo "${conf}" | grep AP_PASSWD | cut -c 11-`
export ESSID=`echo "${conf}" | grep ESSID | cut -c 7-`
export AP_SSID=`echo "${conf}" | grep AP_SSID | cut -c 9-`
if [ "${WIFI_SWITCH_GPIO}" != "" ]; then
	WIFI_SWITCH_VALUE=`/usr/local/share/script/t_gpio.sh ${WIFI_SWITCH_GPIO}`
	echo "GPIO ${WIFI_SWITCH_GPIO} = ${WIFI_SWITCH_VALUE}"
	if [ "${WIFI_SWITCH_VALUE}" == "0" ]; then
		#send network turned off to RTOS
		if [ -x /usr/bin/SendToRTOS ]; then
			/usr/bin/SendToRTOS net_off
		elif [ -x /usr/bin/boot_done ]; then
			boot_done 1 2 1
		fi
		if [ "${WIFI_EN_GPIO}" != "" ]; then
			if [ -e /proc/ambarella/mmc_fixed_cd ]; then
				mmci=`grep mmc /proc/ambarella/mmc_fixed_cd |awk $'{print $1}'|cut -c 4|tail -n 1`
				echo "${mmci} 0" > /proc/ambarella/mmc_fixed_cd
			else
				echo 0 > /sys/module/ambarella_config/parameters/sd1_slot0_fixed_cd
			fi
			if [ "${WIFI_EN_STATUS}" == "" ]; then
				WIFI_EN_STATUS=1
			fi
			/usr/local/share/script/t_gpio.sh ${WIFI_EN_GPIO} $(($(($WIFI_EN_STATUS + 1)) % 2))
		fi
		exit 0
	fi
fi

if [ "${WIFI_EN_GPIO}" != "" ] && [ -z "`ls /sys/bus/sdio/devices`" ]; then
	wait_mmc_add
fi

#check wifi mode
/usr/local/share/script/load_wifi_testmode.sh "${WIFI_MODE}"

waitagain=1
if [ "`ls /sys/bus/sdio/devices`" != "" ] || [ "`ls /sys/bus/usb/devices`" != "" ]; then
	wait_wlan0
fi
if [ $waitagain -ne 0 ]; then
	echo "There is no WIFI interface!"
	exit 1
fi

echo "found WIFI interface!"

ifconfig wlan0 up

#if [ "${WIFI_MODE}" == "p2p" ] ; then
#	/usr/local/share/script/p2p_start.sh $@
#elif [ "${WIFI_MODE}" == "sta" ] ; then
#	/usr/local/share/script/sta_start.sh $@
#else
#	/usr/local/share/script/ap_start.sh $@
#fi
