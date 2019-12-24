#!/bin/sh
#============================================================================
# make_back.sh
version=1.1
echo "make_back.sh version: " $version 
#============================================================================
# Shell script for creating the blank_sky and stowed_bck file for the special observation
#
# Steps:1) looking for specific blank_sky file using acis_bkgrnd_lookup
# 	2) merging them by dmmerge
#	3) determining the specific exposure time (and ontime, livetime)
#       4) reproject the merged blank_sky file to observational specific wcs and GTI
#	5) reproject the merged stowed_bck file to observational specific wcs and GTI
#
# Requirements: 
#	The working path is correct (in it!)
#	having cleaned evt2 file in this document
#       having stacked aspect solution file in this document
#
#
# Arguments:
#  $1 == ROOT name of the events file (e.g., evt2file_new_clean)
#        (def =${events_root})
#  $2 == Input list of aspect solution file(s) (e.g., pcad_asol1.lis).
#  $3 == single ccd number (e.g., 7; overriding the default multiple ccd choice)
#
# Example: 
#  make_back.e  ${events_root} asol_file "0 1 2 3" > make_expmap.log
#  tail make_expmap.log
#
# Outputs:
# 
# ${events_root}_bl.fits
# ${events_root}_bs.fits
#
# written by sw, April 23, 2010
# modified by sw, September 10, 2012
#
# Note: 1).Some Waring like that: 
#          # reproject_events (CIAO 4.2): Warning: Aspect solution covers 
#            time period 386537702.978140:386563453.029446
#            Your data includes time outside this interval 
#            386537702.816055:386562760.397438
#            exists, for example in 10985 & 12130. I have no idea why it happens
#       2).There is no stowed_bck data of CCD acis-s4 (or acis8), so the 
#          stowed_bck file doesn't contain this piece of CCD even in aciss 
#          obs-mode.
#============================================================================
if [ "$1" = "" ]
then
	if [ -f acis*_evt2.fits ]
	then 
	 events_root=`ls acis*_evt2.fits  | cut -d. -f1` 
	else
	 echo "This file acis*_evt2.fits does not exist!"
	 exit -1
	fi
else
	events_root=$1
fi
echo 'events_root = ' $events_root

if [ "$2" = "" ]
then
	asol_file=`ls  pcad*.fits`
	if [ -f $asol_file ]
	then 
	 "Use the aspec solution file ${asol_file}!"
	else
	 echo "This file ${asol_file} does not exist!"
	 exit -1
	fi
else 
    asol_file=$2
fi

if [ "$3" = "" ]
then
	if [ "$INSTR" = "aciss" ]
	then 
	    ccd_id="2,3,5,6,7,8" 	
	else
	    ccd_id="0,1,2,3,6,7"
	fi
else
	ccd_id=$3
fi

data_mode=`dmkeypar ${events_root}.fits datamode echo+`
if [ "${data_mode}" == "FAINT" ]
  then
  exclustr="[cols -time]"
else
  if [ "${data_mode}" == "VFAINT" ]
    then
    exclustr="[status=0][cols -time]"
  else
    echo "Do not make stowed_bck file, because the datamode is not right"
  fi
fi

punlearn acis_bkgrnd_lookup
acis_bkgrnd_lookup ${events_root}.fits > blank_list
blank_list=`cat blank_list`
punlearn dmkeypar
gainfile=`dmkeypar ${events_root}.fits gainfile echo+`
echo "Srcfi: ${gainfile}"
for bl in ${blank_list}
  do
  ccd=`dmkeypar ${bl} ccd_id echo+`
  gainfile=`dmkeypar ${bl} gainfile echo+`
  echo "CCD ${ccd}: ${gainfile}"
done
stow_list=`ls $CALDB/data/chandra/acis/bkgrnd/*stow*cti*`
for st in ${stow_list}
  do
  ccd=`dmkeypar ${st} ccd_id echo+`
  gainfile=`dmkeypar ${st} gainfile echo+`
  echo "CCD ${ccd}: ${gainfile}"
done

punlearn dmmerge
dmmerge @blank_list blank_sky.fits clobber=yes

if [ -f bck_exp_infor ]
then
   rm -f bck_exp_infor
fi
for c in blank_sky.fits ${blank_list}
  do
  exp=`dmkeypar ${c} exposure echo+`
  echo "${c}: ${exp}" >> bck_exp_infor
  echo "${c}:" >> bck_exp_infor
  for b in exposure ontime livetime
    do
    exp=`dmkeypar $c $b echo+`
    echo "${b}: ${exp}" >> bck_exp_infor
  done
done
rm -f blank_list


if [ "${INSTR}" == "aciss" ]
then
   test_bl=`acis_bkgrnd_lookup "${events_root}.fits[ccd_id=7]"`
else
  if [ "${INSTR}" == "acisi" ]
  then
    test_bl=`acis_bkgrnd_lookup "${events_root}.fits[ccd_id=0]"`
  else
    echo "Please set environment parameter ${INSTR}."
    exit -1
  fi
fi
exp=`dmkeypar ${test_bl} exposure echo+`
punlearn dmhedit
for b in exposure ontime livetime
  do
  dmhedit blank_sky.fits fi="" op=add ke=${b} va=${exp}
  dmkeypar blank_sky.fits $b echo+
done

punlearn reproject_events
reproject_events infile="blank_sky.fits${exclustr}" outfile=${events_root}_bl.fits aspect=@asol_file match=${events_root}.fits random=0 clobber=yes
echo "Exposure time of blank_sky (evaluated from CCD):"
for b in exposure ontime livetime
  do
  dmkeypar ${events_root}_bl.fits ${b} echo+
done
rm -f blank_sky.fits

punlearn reproject_events
mjd_obs=`dmkeypar ${events_root}.fits mjd_obs echo+`
if [ $(echo "${mjd_obs} < 53614.0" | bc) == 1 ] 
then
   tail="old"
else
   if [ $(echo "${mjd_obs} > 55095.0" | bc) == 1 ]
     then
     tail="new"
   else
     tail="med"
   fi
fi
reproject_events infile="$CALDB/data/chandra/acis/bkgrnd/stowed_bck_${tail}.fits${exclustr}" \
  outfile=${events_root}_bs.fits aspect=@asol_file match=${events_root}.fits random=0 clobber=yes

#rm -f stow_mat.fits
echo "Exposure of stowed_bck (new:240ks, med:367ks, old:415ks, stowed:613ks):"
exp=`dmkeypar ${events_root}_bs.fits exposure echo+`
for b in exposure ontime livetime
  do
  dmkeypar ${events_root}_bs.fits ${b} echo+
  dmhedit ${events_root}_bs.fits fi="" op=add ke=${b} va=${exp}
done
if [ "${INSTR}" == "aciss" ]
then
   echo "Please check the stowed_bck file, which does not contain CCD acis-s4 (or acis-8)."
fi

# End of Script

