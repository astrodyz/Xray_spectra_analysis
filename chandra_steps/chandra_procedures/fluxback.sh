#!/bin/sh
#==========================================================================
# fluxback.sh
version=0.0
echo "fluxback.sh version: " $version 
#==========================================================================
# Shell script for dividing the instrumental background by corresponding 
# exposure map
#
# Steps:1) extract the background images according the energy bands;
#       2) normalize the individual background images to make them look 
#          like under source exposures;
#	      3) cast the normalized background images to aviod hot pixels;
#       4) divide the source exposure map 
#
# Requirements: 
#       variable $INSTR should be set as 'aciss' or 'acisi'
#
# Arguments:
#  $1 == Input of ObsID
#  $2 == Input of the name of instrumental background file
#  $3 == Input of bands names (as defined by Chandra source catalog)
#  $4 == Input of image bin (default: 2)
#  $5 == Input of CCD chips 
#
# Example: 
#  fluxback.sh "8210" "8210_bs.fits" "broad soft medium hard" 2
#
# Outputs:
# ${events_root}bnew_${band}_cast.fits:  background with exptime of major CCD of 
#    background and normalization according to the counts rate of cosmic band
# ${events_root}bnorm_${band}_cast.fits: background with exptime of source obs 
#    and normalization according to the counts rate of cosmic band
# ${events_root}b_${band}.fits: background flux map which is generated from
#    ${events_root}bnorm_${band}.fits dividing by corresponding source
#    exposure map (${band}_thresh.expmap)
#
# Changing "bnorm", "bnew", and "b" into "bnormerr", "bnewerr", and "berr" 
#    respectively are their corresponding Poission error map.
#
# written by sw, September 20th, 2012
# Modified by sw, October 21st, 2013, to add the calculation of the background 
# errors.
# Modified by sw, November 8th, 2013, some modifications:
#   1. The exchange between argument 4 and argument 5 has been confirmed;
#   2. The binning process has been applied to the events list instead of 
#      processed images. I believe the DM arguments of binning for events 
#      list and image have different effects;
#   3. The calculation of background errors have been parameterized;
#   4. The names of final processed images have been straightfied;
#   5. The calculation of ${bnorm} and ${exprat} parameters have considered 
#      the situation that there is no counts on some specific CCDs (most 
#      likely due to those CCDs are not included in the specific FOV).
#==========================================================================

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
   if [ -f *_bs.fits ]
   then 
      backfile=`ls *_bs.fits`
   else
      echo "This instrumental background file *_bs.fits does not exist!"
      exit -1
   fi
else
   backfile=$2
fi

if [ "$3" = "" ]
then
   bands="broad ultrasoft soft medium hard"
else 
   bands=$3
fi

if [ "$4" = "" ]
then
   binned=2
else
   binned=$4
fi

if [ "$5" = "" ] 
then 
   if [ -f ../repro/*repro*fov*fits ]
   then 
      fovfile=`ls ../repro/*repro*fov*fits`
   else
      echo "The field-of-view file does not exist! You should give one."
      exit -1
   fi
else
   fovfile=$5
fi

fovheader=`echo ${fovfile} | cut -c1`
if [ "$6" = "" ]
then
  if [ "${fovheader}" != "x" ]
    then
    ccd=`dmlist "${fovfile}[cols ccd_id]" opt=data | grep "^    " | awk '{print $2}'`
  else
    echo "The FOV file does not work! Please set the ccd_id parameter."
    exit -1
  fi 
else
   ccd=$6
fi

if [ "$7" = "" ]
then
   fluxdir="../flux"
else
   fluxdir=$7
fi

if [ "${INSTR}" = "aciss" ]
then 
   cosband="10000:14000"
else
   cosband="10000:12000"
fi

if [ "${fovheader}" = "x" ]
  then
  xygrids=${fovfile}
else
  punlearn get_fov_limits
  ccd_id=`echo ${ccd} | sed 's/ /,/g'`
  xygrids=`get_fov_limits infile="${fovfile}[ccd_id=${ccd_id}]" pixsize=${binned} | sed -n '4p'`
fi
dmcopy "${events_root}.fits[bin ${xygrids}][energy=2000:7200]" \
  temp_${events_root}_bin${binned}.fits clobber=yes

# normalize the background file CCD by CCD
echo "file: ${events_root}" > norminfor
punlearn dmimgcalc
pset dmimgcalc mode=h
pset dmimgcalc verbose=3
pset dmimgcalc clobber=yes
punlearn dmimgthresh
pset dmimgthresh cut=1.5%
pset dmimgthresh value=0.0
pset dmimgthresh verbose=3
pset dmimgthresh mode=h
pset dmimgthresh clobber=yes
punlearn reproject_image
pset reproject_image method=sum
pset reproject_image mode=h
pset reproject_image verbose=3
pset reproject_image clobber=yes
punlearn dmstat
punlearn dmcopy
pset dmcopy clobber=yes

# Generate the normalization for the instrumental background (CCD by CCD) 
# bnorm is the factor to src_exposure, bexprat is to background exposure
echo "Processing CCD chips:" ${ccd}
if [ -f norminfor ] 
then
    rm norminfor
fi
for ccd_id in ${ccd}
  do
  bck_cts=`dmstat "${backfile}[ccd_id=${ccd_id}][energy=${cosband}][cols energy]" | grep "good:" | awk '{printf("%d",$2)}'`
  src_cts=`dmstat "${events_root}.fits[ccd_id=${ccd_id}][energy=${cosband}][cols energy]" | grep "good:" | awk '{printf("%d",$2)}'`
  if [ "${src_cts}" = "0" ]
    then
    bnorm=`echo "scale=7;0.000" | bc -l`
    bexprat=`echo "0.000" | awk '{printf("%9.7f",$1)}'`
  else
    src_exp=`dmkeypar ${events_root}.fits exposur${ccd_id} echo+`
    bck_exp=`dmkeypar ${backfile} exposur${ccd_id} echo+`
    bexpnew=`echo "${bck_cts} * ${src_exp} / ${src_cts}" | bc -l`
    bexprat=`echo "${bck_exp} / ${bexpnew}" | bc -l | awk '{printf("%9.7f",$1)}'`
    bnorm=`echo "scale=7;${src_cts} / ${bck_cts}" | bc -l`
  fi
  echo "${ccd_id}: 0${bnorm} ${bexprat}" >> norminfor
done

for band in ${bands}
  do
  echo "Now working on band:" ${band}
  expstr=`cat ${PUBDIR}/cal_scripts/chandra_band_def | grep "^${band}"`
  enlow=`echo ${expstr} | awk '{printf("%s\n",$4)}'`
  enhig=`echo ${expstr} | awk '{printf("%s\n",$5)}'`
  enlowev=`echo "${enlow} * 1000" | bc -l`
  enhigev=`echo "${enhig} * 1000" | bc -l`

  # Normalize the instrumental background, two kinds of bck are derived: 
  # the one with src_exposure (bnorm) and the one with the background 
  # exposure (bnew)
  for ccd_id in ${ccd}
    do
    echo "Now casting CCD:" ${ccd_id}
    
    dmcopy "${backfile}[ccd_id=${ccd_id}][energy=${enlowev}:${enhigev}][bin ${xygrids}][opt type=i5]" temp_${events_root}b_${band}_${ccd_id}.fits
    pset dmimgcalc infile=temp_${events_root}b_${band}_${ccd_id}.fits
    pset dmimgcalc infile2=NONE
    pset dmimgcalc operation=add

    bnorm=`cat norminfor | grep "^${ccd_id}:" | cut -d' ' -f2`
    pset dmimgcalc weight=${bnorm} 
    pset dmimgcalc outfile="temp_${events_root}bnorm_${band}_${ccd_id}.fits"
    dmimgcalc
    echo "temp_${events_root}bnorm_${band}_${ccd_id}.fits" >> temp_bnorm_${band}.list
    pset dmimgcalc weight=1
    pset dmimgcalc operation="imgout=(sqrt(img1 * ${bnorm}))"
    pset dmimgcalc outfile="temp_${events_root}bnormerr_${band}_${ccd_id}.fits"
    dmimgcalc
    echo "temp_${events_root}bnormerr_${band}_${ccd_id}.fits" >> temp_bnormerr_${band}.list

    bexprat=`cat norminfor | grep "^${ccd_id}:" | cut -d' ' -f3`
    pset dmimgcalc weight=${bexprat}
    pset dmimgcalc outfile="temp_${events_root}bnew_${band}_${ccd_id}.fits"
    dmimgcalc
    echo "temp_${events_root}bnew_${band}_${ccd_id}.fits" >> temp_bnew_${band}.list
    pset dmimgcalc weight=1
    pset dmimgcalc operation="imgout=(sqrt(img1 * ${bexprat}))"
    pset dmimgcalc outfile="temp_${events_root}bnewerr_${band}_${ccd_id}.fits"
    dmimgcalc
    echo "temp_${events_root}bnewerr_${band}_${ccd_id}.fits" >> temp_bnewerr_${band}.list
        
  done
  pset reproject_image matchfile="temp_${events_root}_bin${binned}.fits"
  pset reproject_image infile="@temp_bnorm_${band}.list"
  pset reproject_image outfile="${events_root}bnorm_${band}_cast.fits"
  reproject_image
  
  pset reproject_image infile="@temp_bnew_${band}.list"
  pset reproject_image outfile="${events_root}bnew_${band}.fits"
  reproject_image
  
  pset reproject_image infile="@temp_bnormerr_${band}.list"
  pset reproject_image outfile="${events_root}bnormerr_${band}_cast.fits"
  reproject_image
  
  pset reproject_image infile="@temp_bnewerr_${band}.list"
  pset reproject_image outfile="${events_root}bnewerr_${band}.fits"
  reproject_image
  
  pset dmimgthresh infile="${events_root}bnorm_${band}_cast.fits"
  pset dmimgthresh outfile="${events_root}bnorm_${band}_thre.fits"
  pset dmimgthresh expfile="${fluxdir}/${band}_thresh.expmap"
  dmimgthresh
  pset dmimgthresh infile="${events_root}bnormerr_${band}_cast.fits"
  pset dmimgthresh outfile="${events_root}bnormerr_${band}_thre.fits"
  pset dmimgthresh expfile="${fluxdir}/${band}_thresh.expmap"
  dmimgthresh
  
  pset dmimgcalc operation=div
  pset dmimgcalc infile="${events_root}bnorm_${band}_thre.fits"
  pset dmimgcalc infile2="${fluxdir}/${band}_thresh.expmap"
  pset dmimgcalc outfile=${events_root}b_${band}.fits
  pset dmimgcalc weight=1.0
  dmimgcalc
  pset dmimgcalc infile="${events_root}bnormerr_${band}_thre.fits"
  pset dmimgcalc outfile=${events_root}berr_${band}.fits
  dmimgcalc

  # Set the exposure and livetime keywords of the background file with 
  # src_exposure the the src_exposure
  expo=`dmkeypar ${events_root}.fits exposure echo+`
  for c in exposure livetime ontime
    do
    for b in bnorm bnormerr
    do
      for d in cast thre
      do 
        dmhedit "${events_root}${b}_${band}_${d}.fits" fi="" op=add \
          ke=${c} va=${expo}
      done
    done
    for b in b berr
    do
      dmhedit "${events_root}${b}_${band}.fits" fi="" op=add ke=${c} \
        va=${expo}
    done
  done
  # ADD Oct 23, 2015, the exposure time in "bnew" seems multiplied with N_CCD
  expo=`dmkeypar ${backfile} exposure echo+`
  for d in bnew bnewerr
  do
    for c in exposure livetime ontime
    do
      dmhedit "${events_root}${d}_${band}.fits" fi="" op=add ke=${c} va=${expo}
    done
  done

echo "Band ${band} is done!"
done

echo "background flux conversion has been done!"
rm temp_*

# END
  

