#!/bin/bash

PROPERTIES_FILE=build.properties
EXECUTABLE_NAME=ZZT
OUTPUT_ARCHIVE=
TPC_DEFINES="CPU8086"
FPC_DEFINES=""
TEMP_PATH=$(mktemp -d /tmp/zoo.XXXXXXXXXXXX)
CLEANUP=yes
FREE_PASCAL=
ARCH=i8086
FPC_BINARY=ppcross8086
ENGINE=ZZT
PLATFORM=msdos
PLATFORM_UNIT_LOWER=dos
PLATFORM_UNIT=DOS
EXTMEM_STUB=
DEBUG_BUILD=
NATIVE_TOOLS_BUILD=
TPC_ARGS=""
FPC_ARGS=""
NATIVE_BUILD=

# Parse arguments

OPTIND=1
while getopts "a:d:e:n:o:p:rg" opt; do
	case "$opt" in
	a)
		IFS='-' read -ra OPTARGARCH <<< "$OPTARG"
		case "${OPTARGARCH[0]}" in
		tp55)
			FREE_PASCAL=
			;;
		fpc)
			FREE_PASCAL=yes
			;;
		*)
			echo "Unknown compiler ${OPTARGARCH[0]}"
			exit 1
			;;
		esac
		ARCH="${OPTARGARCH[1]}"
		case "$ARCH" in
		native)
			FPC_BINARY=fpc
			NATIVE_BUILD=yes
			;;
		native_x86_64)
			FPC_BINARY=fpc
			FPC_ARGS="$FPC_ARGS"' '"-Px86_64"
			NATIVE_BUILD=yes
			;;
		native_aarch64)
			FPC_BINARY=fpc
			FPC_ARGS="$FPC_ARGS"' '"-Paarch64"
			NATIVE_BUILD=yes
			;;
		i8086)
			FPC_BINARY=ppcross8086
			;;
		m68k)
			FPC_BINARY=ppcross68k
			;;
		i386)
#			FPC_BINARY=ppc386
#			if [ ! -x "$(command -v $FPC_BINARY)" ]; then
				FPC_BINARY=ppcross386
#			fi
			;;
		x86_64)
#			FPC_BINARY=ppcx64
#			if [ ! -x "$(command -v $FPC_BINARY)" ]; then
				FPC_BINARY=ppcrossx64
#			fi
			;;
		aarch64)
#			FPC_BINARY=ppca64
#			if [ ! -x "$(command -v $FPC_BINARY)" ]; then
				FPC_BINARY=ppcrossa64
#			fi
			;;
		arm)
			FPC_BINARY=ppcrossarm
			;;
		*)
			echo "Unknown architecture $ARCH"
			exit 1
			;;
		esac
		PLATFORM="${OPTARGARCH[2]}"
		PLATFORM_UNIT_LOWER="${OPTARGARCH[3]}"
		PLATFORM_UNIT="${PLATFORM_UNIT_LOWER^^}"
		;;
	d)
		if [ "$OPTARG" = "NOEXTMEM" ]; then
			EXTMEM_STUB=true
		fi
		FPC_DEFINES=$FPC_DEFINES" -d"$OPTARG
		if [ -n "$TPC_DEFINES" ]; then
			TPC_DEFINES=$TPC_DEFINES","$OPTARG
		else
			TPC_DEFINES=$OPTARG
		fi
		;;
	e)
		EXECUTABLE_NAME=$OPTARG
		;;
	n)
		ENGINE=$OPTARG
		;;
	o)
		OUTPUT_ARCHIVE=$OPTARG
		;;
	p)
		PROPERTIES_FILE=$OPTARG
		;;
	r)
		CLEANUP=
		;;
	g)
		DEBUG_BUILD=yes
		;;
	esac
done
shift $((OPTIND - 1))

if [ ! -n "$OUTPUT_ARCHIVE" ]; then
	OUTPUT_ARCHIVE="$ARCH"-"$PLATFORM"-"$PLATFORM_UNIT_LOWER".zip
	if [ -n "$FREE_PASCAL" ]; then
		OUTPUT_ARCHIVE=zoo-fpc-"$OUTPUT_ARCHIVE"
	else
		OUTPUT_ARCHIVE=zoo-tpc-"$OUTPUT_ARCHIVE"
	fi
fi

# Add E_$ENGINE define.
FPC_DEFINES=$FPC_DEFINES" -dE_"$ENGINE
if [ -n "$TPC_DEFINES" ]; then
	TPC_DEFINES=$TPC_DEFINES",E_"$ENGINE
else
	TPC_DEFINES="E_"$ENGINE
fi

# Populate TPC_ARGS and FPC_ARGS.
if [ -z "$DEBUG_BUILD" ]; then
	TPC_ARGS='/$D- /$L- /$S-'
fi
if [ -n "$TPC_DEFINES" ]; then
	# Defines are handled elsewhere.
	TPC_ARGS="$TPC_ARGS"
	FPC_ARGS="$FPC_ARGS"' '"$FPC_DEFINES"
fi

if [ ! -d "OUTPUT" ]; then
	mkdir "OUTPUT"
fi

echo "Preparing Pascal code..."

mkdir -p VENDOR

for i in DOC HEADERS RES SRC SYSTEM TOOLS VENDOR LICENSE.TXT; do
	cp -R "$i" "$TEMP_PATH"/
done
cp -R "$TEMP_PATH"/SYSTEM/*.BAT "$TEMP_PATH"/

for i in BUILD DIST; do
	mkdir "$TEMP_PATH"/"$i"
done

# Replace symbols with ones from PROPERTIES_FILE
if [ -f "$PROPERTIES_FILE" ]; then
	while IFS='=' read -r KEY VALUE; do
		cd DOC
		for i in *.HLP; do
			sed -i -e 's#%'"$KEY"'%#'"$VALUE"'#g' "$i"
		done
		cd ..
		for i in `find "$TEMP_PATH"/SRC -type f`; do
			sed -i -e 's#%'"$KEY"'%#'"$VALUE"'#g' "$i"
		done
	done < "$PROPERTIES_FILE"
fi
# Replace %ENGINE% with configured engine name
for i in `find "$TEMP_PATH"/SRC -type f`; do
	sed -i -e 's#%ENGINE%#'"$ENGINE"'#g' "$i"
done
# HACK: Replace WorldExt with World in non-ZZT engines
if [ "$ENGINE" != "ZZT" ]; then
	for i in `find "$TEMP_PATH"/SRC -type f`; do
		sed -i -e 's#WorldExt#World#g' "$i"
	done
fi

FPC_BINARY_PATH="$FPC_PATH"
if [ -x "$(command -v $FPC_BINARY)" ]; then
	FPC_BINARY_PATH=$(realpath $(dirname $(command -v $FPC_BINARY))/..)
elif [ ! -f "$FPC_BINARY_PATH"/bin/"$FPC_BINARY" ]; then
	FPC_BINARY=fpc
	if [ -x "$(command -v $FPC_BINARY)" ]; then
		FPC_BINARY_PATH=$(realpath $(dirname $(command -v $FPC_BINARY))/..)
	fi
fi
if [ -x "$(command -v fpc)" ]; then
	NATIVE_TOOLS_BUILD=yes
fi
if [ -z "$FPC_LIBRARY_PATH" ]; then
	FPC_LIBRARY_PATH="$FPC_PATH"/lib
fi

sed -i -e 's#%COMPARGS%#'"$TPC_ARGS"'#g' \
       -e 's#%ENGINE%#'"$ENGINE"'#g' "$TEMP_PATH"/BUILD.BAT
sed -i -e 's#%ENGINE%#'"$ENGINE"'#g' "$TEMP_PATH"/RUNTOOLS.BAT
sed -i -e 's#%FPC_PATH%#'"$FPC_BINARY_PATH"'#g' "$TEMP_PATH"/SYSTEM/fpc.datpack.cfg
for i in `ls "$TEMP_PATH"/SYSTEM/fpc.*.cfg`; do
	sed -i -e 's#%FPC_PATH%#'"$FPC_BINARY_PATH"'#g' \
	       -e 's#%FPC_LIBRARY_PATH%#'"$FPC_LIBRARY_PATH"'#g' \
	       -e 's#%HOME%#'"$HOME"'#g' "$i"
done
echo "Compiling Pascal code..."

RETURN_PATH=$(pwd)
cd "$TEMP_PATH"

cp DOC/BASIC/* DOC/
if [ -d DOC/"$PLATFORM_UNIT" ]; then
	cp DOC/"$PLATFORM_UNIT"/* DOC/
fi
if [ -d DOC/"$ENGINE" ]; then
	cp DOC/"$ENGINE"/* DOC/
fi

if [ -n "$FREE_PASCAL" ]; then
	if [ -n "$NATIVE_TOOLS_BUILD" ]; then
		cd TOOLS

		echo "[ Building DATPACK ]"
		fpc DATPACK.PAS
		mv DATPACK ../BUILD/

		echo "[ Building BIN2PAS ]"
		fpc BIN2PAS.PAS
		mv BIN2PAS ../BUILD/

		cd ..
	fi

	cd SYSTEM
	touch ../SRC/fpc.cfg
	echo '-FuBASIC' >> ../SRC/fpc.cfg
	echo '-FuE_'$ENGINE >> ../SRC/fpc.cfg
	if [ -f fpc."$ARCH"."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg ]; then
		cat fpc."$ARCH"."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
	elif [ -f fpc."$ARCH"."$PLATFORM".any.cfg ]; then
		cat fpc."$ARCH"."$PLATFORM".any.cfg >> ../SRC/fpc.cfg
		if [ -f fpc.any.any."$PLATFORM_UNIT_LOWER".cfg ]; then
			cat fpc.any.any."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
		else
			echo '-Fu'"$PLATFORM_UNIT" >> ../SRC/fpc.cfg
		fi
	else
		if [ -f fpc."$ARCH".any.any.cfg ]; then
			cat fpc."$ARCH".any.any.cfg >> ../SRC/fpc.cfg
		fi
		if [ -f fpc.any."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg ]; then
			cat fpc.any."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
		else
			if [ -f fpc.any."$PLATFORM".any.cfg ]; then
				cat fpc.any."$PLATFORM".any.cfg >> ../SRC/fpc.cfg
			else
				echo '-T'"$PLATFORM" >> ../SRC/fpc.cfg
			fi
			if [ -f fpc.any.any."$PLATFORM_UNIT_LOWER".cfg ]; then
				cat fpc.any.any."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
			else
				echo '-Fu'"$PLATFORM_UNIT" >> ../SRC/fpc.cfg
			fi
		fi
	fi
	cat fpc.base.cfg >> ../SRC/fpc.cfg
	if [ -n "$DEBUG_BUILD" ]; then
		cat fpc.base.debug.cfg >> ../SRC/fpc.cfg
	else
		cat fpc.base.release.cfg >> ../SRC/fpc.cfg
	fi

	cd ..
	if [ -n "$NATIVE_TOOLS_BUILD" ]; then
		BUILD/BIN2PAS SRC/ASCII.CHR SRC/F_ASCII.PAS F_ASCII
		cd DOC
		../BUILD/DATPACK /C ../BUILD/"$ENGINE".DAT *.*
		cd ..
	else
		sed -i -e "s/^BUILD$/RUNTOOLS/" SYSTEM/dosbox.conf
		touch BUILD.LOG
		SDL_VIDEODRIVER=dummy dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
		tail --pid $! -n +1 -f BUILD.LOG
	fi

	cd SRC
	if [ -n "$NATIVE_BUILD" ]; then
		mv fpc.cfg fpc2.cfg
		FPC_ARGS="$FPC_ARGS"' '"@fpc2.cfg"
	fi
	echo "[ Building ZZT.EXE ]"
	"$FPC_BINARY_PATH"/bin/"$FPC_BINARY" $FPC_ARGS ZZT.PAS
	if [ -f ZZT.exe ]; then
		cp ZZT.exe ../BUILD/ZZT.EXE
		cp ZZT.exe ../DIST/"$EXECUTABLE_NAME".EXE
	elif [ -f ZZT ]; then
		cp ZZT ../BUILD/ZZT
		cp ZZT ../DIST/"$EXECUTABLE_NAME"
	else
		cd "$RETURN_PATH"
		# rm -rf "$TEMP_PATH"
		exit 1
	fi
	cd ..
else
	# HACK! NEC98 requires SRC/DOS/EXTMEM.PAS, as the underlying standards are
	# the same. (We do this on Free Pascal via fpc.any.any.nec98.cfg.)
	cp SRC/DOS/EXTMEM.PAS SRC/EXTMEM.PAS 2>/dev/null

	cp SRC/"$PLATFORM_UNIT"/*.PAS SRC/ 2>/dev/null
	cp SRC/"$PLATFORM_UNIT"/*.INC SRC/ 2>/dev/null

	cp SRC/E_"$ENGINE"/*.PAS SRC/ 2>/dev/null
	cp SRC/E_"$ENGINE"/*.INC SRC/ 2>/dev/null

	if [ "$EXTMEM_STUB" = "true" ]; then
		cp SRC/EXTMEM_S.PAS SRC/EXTMEM.PAS 2>/dev/null
	fi

	touch TPC.CFG
	echo "$TPC_DEFINES" | tr ',' '\n' | while read def; do
		echo -n -e "/D"$def\\r\\n >> TPC.CFG
	done

	touch BUILD.LOG
	SDL_VIDEODRIVER=dummy dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
	tail --pid $! -n +1 -f BUILD.LOG
fi

# TODO
#if [ ! -f BUILD/ZZT.EXE ]; then
#       cd "$RETURN_PATH"
#       # rm -r "$TEMP_PATH"
#       exit 1
#fi

# Post-processing

echo "Packaging..."

if [ "$ARCH" = "i8086" ] && [ "$PLATFORM" = "msdos" ]; then
	if [ -f DIST/"$EXECUTABLE_NAME".EXE ]; then
		rm DIST/"$EXECUTABLE_NAME".EXE
	fi
	if [ ! -x "$(command -v upx)" ]; then
		echo "Not compressing - UPX is not installed!"
		cp BUILD/ZZT.EXE DIST/"$EXECUTABLE_NAME".EXE
	else
		echo "Compressing..."
		upx --8086 -9 -o DIST/"$EXECUTABLE_NAME".EXE BUILD/ZZT.EXE
	fi
fi

if [ -f BUILD/$ENGINE.DAT ]; then
	cp BUILD/$ENGINE.DAT DIST/
fi
cp LICENSE.TXT DIST/
cp RES/BASIC/* DIST/
if [ -d RES/"$PLATFORM_UNIT" ]; then
	cp RES/"$PLATFORM_UNIT"/* DIST/
fi
if [ -d RES/"$ENGINE" ]; then
	cp RES/"$ENGINE"/* DIST/
fi
if [ -d "$RETURN_PATH"/SYSLIBS/"$PLATFORM"-"$PLATFORM_UNIT_LOWER" ]; then
	cp "$RETURN_PATH"/SYSLIBS/"$PLATFORM"-"$PLATFORM_UNIT_LOWER"/* DIST/
fi

cd DIST
zip -9 -r "$RETURN_PATH"/OUTPUT/"$OUTPUT_ARCHIVE" .
cd ..

cd "$RETURN_PATH"
if [ -n "$CLEANUP" ]; then
	rm -rf "$TEMP_PATH"
else
	echo 'Not cleaning up as requested; work directory: '"$TEMP_PATH"
fi
