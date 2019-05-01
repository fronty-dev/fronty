#!/bin/bash
#This is the build script for packages
#Filename build_package.sh
#Date 20190226
#Version 0.1
#Author AL
 
# Exit codes
# 0 - worked successfully
# 1 - configg file missing
# 2 - error with 64 bit source download
# 3 - error with 32 bit source download
# 4 - SlackBuild files not available
# 5 - compilation failed
# 6 - script already running - code to be added - flag file perhaps?

# ***To add***
# Add code to check if there is already an SBo package built, if so use it 
# instead of downloading and building from scratch.  Only check if $prg/$version 
# exists and $prg not installed.  Upgrade in separate script.
# Add code to deal with multiple downloads, eg GeoIP, has 6 extras.
# Improve code to assign values to vars instead of echo $varname | cut -f x -d, etc if possible.
# More error checking
# ***End of To add section***

#Get the apps category from category.apps first
#Get the values for dwnlddir and slackver - if the config file is missing, print
#an error and exit
if [ ! -f /etc/fronty/fronty.conf ]; then
	echo "/etc/fronty/fronty.conf missing!  Exiting..."
	exit 1
fi
source /etc/fronty/fronty.conf

#Export the variables so pre- and post- scripts have them if needed
export source=$source
export config=$config
export scripts=$scripts
export slackver=$slackver
export fronty_logfile=$fronty_logfile

#progs variable lists all the packages required for the install.
#Change packages to the list of packages that need installing, in order.
progs=$(grep ,$pkg, $config/category.apps.deps | cut -f4 -d,)" "$pkg

#Check category.apps.index and category.apps.data are available, if not print an error and run the script.
if [ ! -f $config/category.apps.index ] || [ ! -f $config/category.apps.data ]; then
	echo "A category index or data file is missing, running script..."
	$basedir/build_repo.sh
fi

#Set app top the name of the package being installed, the last (or only one) in progs
app=$(echo $progs | rev | cut -f1 -d" " | cut -b1- | rev)
echo "Start build of $app" >> $fronty_logfile
# Check if each package exists.  If not it may be a typo and progs is incrorrect.
# Exit if any is incorrect
for prgchk in $progs; do
	pkg_exists=$(grep ,$prgchk, $config/category.apps.index | head -1 | cut -f2 -d,)
	if [ -z $pkg_exists ]; then
		echo "Package "$prgchk" doesn't exist, or it is a typo."
		echo "Please fix and rerun.  Exiting"
		echo "Package "$prgchk" doesn't exist, or it is a typo." >> $fronty_logfile
		exit 7
	fi
done
#Now go through each package in turn, check if it has a directory, if not get the download info and Slackbuild files
#from category.apps.data, download, check md5sum and continue.
for prg in $progs; do
	cd $source
	echo "Date :" `date +%Y%m%d-%H%M%S` " Start package : " $prg >> $fronty_logfile
	# Check if the package exists.  If not it may be a typo and progs is incorrect.
	#Fields in category.apps.data:
	#category,$prgnam,$version,$homepage,$download,$md5sum,$dwnld_x86_64,$md5sum_x86_64,$requires
	#Get the pkg info and split it into separate variables
	progcat=$(grep ","$prg"," $config/category.apps.index)
	progparams=$(grep $progcat $config/category.apps.data)
	category=$(echo $progparams | cut -f1 -d,)
	version=$(echo $progparams | cut -f3 -d,)
	dwnld=$(echo $progparams | cut -f5 -d,)
	md5sum=$(echo $progparams | cut -f6 -d,)
	dwnld_x86_64=$(echo $progparams | cut -f7 -d,)
	d5sum_x86_64=$(echo $progparams | cut -f8 -d,)
	echo "progparams : "$progparams >> $fronty_logfile

	#Check if the package is installed, if so skip this and go onto the next package
	pkg_found=$(ls /var/log/packages | grep $prg | rev | cut -f4- -d- | rev | head -1)
	if [ ! -z $pkg_found ] && [ $pkg_found != $prg ] || [ -z $pkg_found ]; then
		echo "Package "$prg" not installed" >> $fronty_logfile
		if [ ! -d $prg ]; then 
			#Create the dir with the prg as its name
			mkdir $prg
			echo "Created dir for "$prg >> $fronty_logfile
			cd $prg
			#Create the dir with the version as its name
			mkdir $version
			echo "Created dir version "$version" for "$prg >> $fronty_logfile
			cd $version
		else
			cd $prg
			if [ -d $version ]; then 
				cd $version
			else
				mkdir $version
				cd $version
			fi
		fi
		# Now for some processing of the downloads and md5sums - some packages have more than one download
		# and because of this the downloads have to be in a file.  Variables cannot hold newline characters.
		# If a variable has spaces in it it causes issues with the -z option (if [ -z varname ...) because
		# only one argument is expected, whereas having a space means there is more than one argument which
		# is why wc -c is used.
		# 64 bit downloads
		if [ `echo $dwnld_x86_64 | wc -c` -gt 1 ]; then
			echo $dwnld_x86_64 | sed s/\ /\\n/g > link64
			echo $dwnld_x86_64 | sed s/\ /\\n/g | rev | cut -f1 -d\/ | rev > file64
			echo $md5sum_x86_64 | sed s/\ /\\n/g > md5sum64-tmp
			paste md5sum64-tmp file64 | sed s/\\t/"  "/g > md5sum64
		elif [ `echo $dwnld | wc -c` -gt 1 ]; then
			echo $dwnld | sed s/\ /\\n/g > link32
			echo $dwnld | sed s/\ /\\n/g | rev | cut -f1 -d\/ | rev > file32
			echo $md5sum | sed s/\ /\\n/g > md5sum32-tmp
			paste md5sum32-tmp file32 | sed s/\\t/"  "/g > md5sum32
		fi
	
		# If the source has already been downloaded don't download it again.
		# check the machine arch first then check if there is a 64 bit or 32 bit download
		if [ `uname -m` == "x86_64" ]; then
			#Is there an x86_64 download, if so download it
			if [ -f file64 ]; then
				#If the file is already here don't download it again.
				for dwnld64 in $(cat file64); do
					if [ ! -f $dwnld64 ]; then
						echo "Fetching x86_64 download "$dwnld64 >> $fronty_logfile
						wget $(grep $dwnld64 link64)
						echo "Download complete for "$dwnld64 >> $fronty_logfile
					fi
					grep $dwnld64 md5sum64 > "md5sum64-"$prg
					md5sum -c "md5sum64-"$prg
					if [ $? != 0 ]; then
						echo "Error with x86_64 downloaded source for " $prg" exiting..." >> $fronty_logfile
						echo >> $fronty_logfile
						exit 2
					fi
					echo "md5sum_x86_64 OK for "$dwnld_x86_64 >> $fronty_logfile
				done
			# There may be a 32 bit download 
			elif [ -f file32 ]; then
				#If the file is already here don't download it again.
				for dwnld32 in $(cat file32); do
					if [ ! -f $dwnld32 ]; then
						echo "Fetching x86 download "$dwnld32 >> $fronty_logfile
						wget $(grep $dwnld32 link32)
						echo "Download complete for "$dwnld32 >> $fronty_logfile
					fi
					grep $dwnld32 md5sum32 > "md5sum32-"$prg
					md5sum -c "md5sum32-"$prg
					if [ $? != 0 ]; then
						echo "Error with downloaded source for " $prg" exiting..." >> $fronty_logfile
						echo >> $fronty_logfile
						exit 3
					fi
					echo "md5sum OK for "$dwnld32 >> $fronty_logfile
				done
			fi
		elif [ `uname -m` == "x86" ] || [ $(uname -m) == "i686" ]; then
			#Download the x86 source
			for dwnld32 in $(cat file32); do
				if [ ! -f $dwnld32 ]; then
					echo "Fetching x86 download "$dwnld32 >> $fronty_logfile
					wget $(grep $dwnld32 link32)
					echo "Download complete for "$dwnld32 >> $fronty_logfile
				fi
				grep $dwnld32 md5sum32 > "md5sum32-"$prg
				md5sum -c "md5sum32-"$prg
				if [ $? != 0 ]; then
					echo "Error with downloaded source for " $prg" exiting..." >> $fronty_logfile
					echo >> $fronty_logfile
					exit 3
				fi
				echo "md5sum OK for "$dwnld32 >> $fronty_logfile
			done
		fi
		# Check the SlackBuild files are available and copy to the source dir
		if [ ! $config/$category/$prg/$prg".SlackBuild" ]; then
			echo $prg".SlackBuild not available, exiting..." >> $fronty_logfile
			echo >> $fronty_logfile
			exit 4
		else	
			cp -R $config/$category/$prg/* .
			echo "Copied "$prg" SlackBuild files...">>$fronty_logfile
			#Commented out the next line as I don't think it is needed.  I don't know why I added it.
		#	BUILD=$(grep ^BUILD $prg".SlackBuild" | cut -f2 -d- | rev | cut -b2- | rev)
		fi

		#If there are any prebuild scripts, run them now.  Postfix has one to remove 
		#sendmail if it is installed
		if [ -f $config/$prg.preoptions ]; then
			echo "Running prebuild script "$prg".preoptions now..>" >> $fronty_logfile
			$config/$prg.preoptions
		fi
		#Run the Slackbuild script
		#Note that some packages may require extra options so add them here in $pkgoptions,
		#from category.apps.options
		#If the SBo package is not present compile, otherwise to the install
		if [ ! -f $prg"-"$version*"SBo"* ]; then
			compiledate=$(date +%Y%m%d-%H%M%S)
			if [ -f $config/$prg.options ]; then
				echo "Compiling with options..." >> $fronty_logfile
				echo >> $fronty_logfile
				source $config/$prg.options
				sh ./$prg.SlackBuild  > ./$prg"_"$compiledate"_build.log"
			else
				echo "Compiling without options..." >> $fronty_logfile
				sh ./$prg.SlackBuild > ./$prg"_"$compiledate"_build.log"
			fi
		
			if [ ! `tail -2 $prg"_"$compiledate"_build.log"|head -1 | rev | cut -f1 -d" "| rev | grep created` ]; then
			 	echo "Compilation of "$prg" failed, check "$prg"_"$compiledate"_build.log and "$fronty_logfile >> ./$prg"_"$compiledate"_build.log"
				echo "Compilation of "$prg" failed, check "$prg"_"$compiledate"_build.log and "$fronty_logfile " "$(date +%Y%m%d-%H%M%S) >> $fronty_logfile
				echo >> $fronty_logfile
				#This should exit the script but it doesn't seem to work
				exit 5
			fi
			pkg=$(tail -2 ./$prg"_"$compiledate"_build.log" | head -1 | cut -b19- | rev | cut -b10- | rev)
			mv $pkg .
			echo $pkg" moved from /tmp to "$(pwd)
		else
			# Package already compiled
			echo $prg" already compiled, SBo exists..." >> $fronty_logfile
		fi
		# If the compile was skipped, an SBo file is present but the var pkg has not been set, so pkgname 
		# will not be set.  Do it here.
		if [ ! -z $pkg ]; then
			pkgname=$(echo $pkg | cut -b6-)
		else
			pkgname=$( ls | grep SBo)
		fi
		echo $pkgname
		#If we have only one package to install, don't add this entry to the log, it will be done at the end.
		if [ $prg != $app ]; then 
			echo "Date :" `date +%Y%m%d-%H%M%S` " Finish "$prg >> $fronty_logfile
		fi
		echo "Installing package... "$pkgname >> $fronty_logfile
		installpkg $pkgname
		touch $source/$prg-$version
		# Run any postoptions scripts		
		if [ -f $config/$prg.postoptions ]; then
			echo "Running postoptions script..." >> $fronty_logfile
			echo >> $fronty_logfile
			$config/$prg.postoptions
		fi
		echo >> $fronty_logfile
	else
		echo "Package "$prg" already installed, skipping..." >> $fronty_logfile
		echo >> $fronty_logfile
	fi
	# Set all  the variables to blank.  Good practice.
	progcat=""
	progparams=""
	category=""
	prgnam=""
	version=""
	homepage=""
	dwnload=""
	md5sum=""
	dwnload_x86_64=""
	md5sum_x86_64=""
	dwnld32=""
	dwnld64=""
	#BUILD=""
	pkgTAR=""
	pkgoptions=""
	prg=""
	app=""
	pkg=""
	pkgname=""
done
echo "Date :" `date +%Y%m%d-%H%M%S` " Finished $app" >> $fronty_logfile
echo "================================================================================" >> $fronty_logfile
echo >> $fronty_logfile
#Add headers to category.apps.index and category.apps.data
