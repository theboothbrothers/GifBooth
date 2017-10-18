#!/bin/bash

# -----------------------------------------------------------------------
#  BUTTON SETTINGS
# -----------------------------------------------------------------------
btnName=MKEYBOARD
btnKeyCode=10
btnKeyPressed=1
btnKeyName=KEY_1


# -----------------------------------------------------------------------
#  CAPTURE SETTINGS
# -----------------------------------------------------------------------
camAperture=11
camShutterSpeed=1/200
camISO=400
camWb="Flash"
camDriveMode="Continuous"
camFocusMode="Manual"
camPictureStyle="User defined 1"
camImgFormat="Smaller JPEG"
camCaptureTarget=1
shootFor=3000ms


# -----------------------------------------------------------------------
#  VIDEO SETTINGS
# -----------------------------------------------------------------------
durationInSec=3
framesPerSec=9
videoResolutionW=1920
videoResolutionH=1080
x264crf=25
x264profile=baseline
x264preset=ultrafast
x264level=1.2



function programButton {

	# determine absolute script path
	MY_NAME="`basename \"$0\"`"
	MY_PATH="`dirname \"$0\"`"
	MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

	# find eventid for button
	eventid=$(cat /proc/bus/input/devices | awk '/'$btnName'/{for(a=0; a>=0; a++) { getline; { if(/kbd/==1) { print $0; exit 0; } } } }' | sed -rn 's/.*(event[[:digit:]]*).*/\1/p')
	echo " > EventID for '$btnName': $eventid"

	# set r/w permissions on eventid for "normal" user
	sudo chmod 666 /dev/input/$eventid

	# remap key to right control button (in order not to unintentionally press a key...)
	xmodmap -e "keycode $btnKeyCode=Control_R"

	# create triggerhappy configuration
	echo "$btnKeyName 1 /bin/bash $MY_PATH/$MY_NAME shoot" > thd.conf

	# open black screen
	killall eom 2> /dev/null
	eom -f images/black.gif &
	sleep 0.5

	# run triggerhappy in non-daemon mode
	thd --socket thd.socket --triggers thd.conf --pidfile thd.pid /dev/input/$eventid
}


function unprogramButton {
	# stop triggerhappy
	th-cmd --socket thd.socket --quit

	# delete triggerhappy config
	rm thd.conf 2> /dev/null

	# unremap key
	xmodmap -e "keycode $btnKeyCode=$btnKeyPressed"
}


function shoot {
	# take frames in burst mode
	gphoto2 --quiet \
		--set-config aperture=$camAperture \
		--set-config shutterspeed=$camShutterSpeed \
		--set-config iso=$camISO \
		--set-config whitebalance="$camWb" \
		--set-config drivemode="$camDriveMode" \
		--set-config focusmode="$camFocusMode" \
		--set-config picturestyle="$camPictureStyle" \
		--set-config imageformat="$camImgFormat" \
		--set-config imageformatsd="$camImgFormat" \
		--set-config capturetarget=$camCaptureTarget \
		--set-config colorspace=sRGB \
		--set-config eosremoterelease="Immediate" --wait-event=$shootFor \
		--set-config eosremoterelease="Release Full"

	# download frames from camera
	gphoto2 --quiet --filename "burst_%03n.jpg" --force-overwrite --get-all-files

	# delete frames from camera
	gphoto2 --quiet --recurse --delete-all-files

	# reset camera
	gphoto2 --quiet --set-config focusmode="One Shot" --set-config drivemode="Single" --set-config imageformat="Large Fine JPEG" --set-config imageformatsd="Large Fine JPEG" --set-config aperture=16 --set-config iso=200 --set-config capturetarget=0
}


function downsize {
	# downsize frames
	for i in burst_*.jpg; do
	    [ -f "$i" ] || break
		gm convert -size x$videoResolutionH -resize x$videoResolutionH "$i" +profile "*" "$i"
	done
}


function convert {
	# convert to mp4
	#  - crop to $videoResultionH * $videoResultionW
	#ffmpeg -y -loglevel error -loop 1 -t $durationInSec -start_number 1 -i burst_%03d.jpg -an -sn -c:v libx264 -vf "crop=$videoResolutionW:$videoResolutionH:in_w/2:in_h/2,fps=$framesPerSec,format=yuv420p" -profile:v $x264profile -preset:v $x264preset -level:v $x264level -crf $x264crf videos/$vidFileName
	#  - do not crop
	ffmpeg -y -loglevel error -loop 1 -t $durationInSec -start_number 1 -i burst_%03d.jpg -an -sn -c:v libx264 -vf "fps=$framesPerSec,format=yuv420p" -profile:v $x264profile -preset:v $x264preset -level:v $x264level -crf $x264crf videos/$vidFileName

	# delete photos
	rm burst_*.jpg
}


function play {
	# kill older mpv sessions
	killall mpv 2> /dev/null

	# play video in fullscreen and endless loop
	mpv --really-quiet --no-audio --loop-file --fullscreen videos/$vidFileName &
}


function ctrl_c {
	killall eom 2> /dev/null
	unprogramButton
	exit 1
}




# catch Ctrl+C
trap ctrl_c SIGINT

echo -----------------------------
case "$1" in
	start)
		echo "PROGRAMMING BUTTON AND WAITING..."
		programButton
		echo " > DONE"
		;;
	shoot)
		th-cmd --socket thd.socket --disable
		echo "SHOOTING..."
		vidFileName=$(date +"tbb_%Y%m%d-%H%M%S.mp4")
		shoot
		downsize
		convert
		play
		echo " > DONE"
		th-cmd --socket thd.socket --enable
		;;
	*)
		echo "ARGUMENT '$1' UNKNOWN!"
		;;
esac
echo -----------------------------
