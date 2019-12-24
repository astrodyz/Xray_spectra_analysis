#!/bin/sh
#==========================================================================
# spec_scr_single.sh
version=0.0
echo "spec_scr_single.sh version: " $version 
#==========================================================================
# Shell script for extracting spectra (source & instrumental background) of  
# extended emission from single observation
#
# Steps:1) Make links of used files for each observation;
# 	    2) Extract the instrmental background spectra by "dmextract";
#	      3) Extract the source spectra and create corresponding response 
#          files by "specextract";
#       4) Normalize the instrumental background spectra according to 
#          the counts rate of cosmic band (10-12 keV for ACISI, 10-14 keV 
#          for ACISS)
#
# Requirements: 
#       variable $INSTR should be set as 'aciss' or 'acisi'
#
# Arguments:
#  $1 == Input of the header of outputs (default: same as current folder)
#  $2 == Input of region file (in WCS coordinate)
#  $3 == Input of directory containing observations (default: current_path/../../..)
#  $4 == Input of the ObsID (default: content of ${workdir}/list)
#
# Example: 
#  spec_scr_single.sh "combine" src.reg "/Users/sunwei/data/snr/0454/chandra" "3847"
#
# Specical Note:
#  1. This is "spec_scr.sh" of single-observation version;
#  2. ${workdir} must be full path name (without "~"!) and not end with "/";
#  3. The observations must have been re-processed by "chandra_repro", 
#     which guarantees the needed files are organized in the sub-directory 
#     "repro" under each ObsID-named directory in ${workdir};
#  4. Assume the spectral folder under ${workdir}/${obsid}/some_name/spec_name/, 
#     which makes the default value of ${workdir} (current_path/../../..) work.
#
# Outputs:
# 
# ${header}_src.pi/arf/rmf: source spectrum and its response file
# ${header}.pi: background spectrum
#
# Inherited from "spec_scr.sh" that written by sw, Oct. 10th, 2012
#==========================================================================

if [ "$1" = "" ]
then
   current_path=`pwd`
   header=`basename ${current_path}`
else
   header=$1
fi

if [ "$2" = "" ]
then
   if [ -f *src*reg ]
   then 
      regfile=`ls *src*reg  | head -1` 
   else
      echo "The region file does not exist!"
      exit -1
   fi
else
   regfile=$2
fi

if [ "$3" = "" ]
then
   current_path=`pwd`
   dirpath=`dirname ${current_path}`
   workdir="${dirpath}/../../.."
else
   workdir=$3
fi

if [ "$4" = "" ]
then
   if [ -f ${workdir}/list ]
   then 
      obsid=`cat ${workdir}/list`
   else 
      echo "No list file under ${workdir}/!"
      echo "Please supply observation list."
      exit -1
   fi
else
   obsid=$4
fi

echo "${workdir}/${obsid}/repro/"
flag=0
if [ ! -f ${workdir}/${obsid}/repro/*evt2*clean.fits ]; then flag=1; fi
if [ ! -f ${workdir}/${obsid}/repro/*repro_bpix*fits ]; then flag=1; fi
if [ ! -f ${workdir}/${obsid}/repro/*msk*fits ]; then flag=1; fi
if [ ! -f ${workdir}/${obsid}/repro/*pbk*fits ]; then flag=1; fi
if [ ! -f ${workdir}/${obsid}/repro/pcadf*asol*fits ]; then flag=1; fi
if [ ! -f ${workdir}/${obsid}/back/${obsid}_bs.fits ]; then flag=1; fi

#echo $flag
if [ "${flag}" = "1" ]; then
   echo "Some needed file(s) is/are missing. Please check."
   exit -1
fi

if [ ${INSTR} = "aciss" ] 
then
   coschannel="685:959"
else
   coschannel="685:822"
fi

ln -s ${workdir}/${obsid}/repro/evt2_clean.fits ${obsid}.fits
ln -s ${workdir}/${obsid}/repro/*repro_bpix1.fits bpix_${obsid}.fits
ln -s ${workdir}/${obsid}/repro/*msk*fits* msk_${obsid}.fits
ln -s ${workdir}/${obsid}/repro/*pbk*fits* pbk_${obsid}.fits
ln -s ${workdir}/${obsid}/back/${obsid}_bs.fits ${obsid}_b.fits
asol_list=`ls ${workdir}/${obsid}/repro/*asol*fits*`
i="1"
for c in ${asol_list}
  do
  cp ${c} asol_${obsid}_${i}.fits
  i=`echo "$i + 1" | bc -l`
done

ls asol_${obsid}_?.fits > asol.lis

# Extract instrumental background by dmextract
punlearn dmextract
pset dmextract infile="${obsid}_b.fits[sky=region(${regfile})][bin pi]"
pset dmextract outfile="${header}.pi"
pset dmextract clobber=yes
pset dmextract verbose=1
pset dmextract mode=h
dmextract

# Extract individual spectra by specextract
punlearn specextract
pset specextract infile="${obsid}.fits[sky=region(${regfile})]"
pset specextract outroot="${header}_src"
pset specextract asp=@asol.lis
pset specextract pbkfile="pbk_${obsid}.fits"
pset specextract mskfile="msk_${obsid}.fits"
pset specextract badpixfile="bpix_${obsid}.fits"
pset specextract combine=no
pset specextract weight=yes correct=no
pset specextract clobber=yes
pset specextract mode=h
pset specextract verbose=1
specextract

# Edit intrumental background header value of response files 
dmhedit ${header}.pi fi="" op=add ke=ancrfile va=${header}_src.warf
dmhedit ${header}.pi fi="" op=add ke=respfile va=${header}_src.wrmf

# Normalize the instrumental background by 10-12keV (686:821 channel) cts_rate
src_cts=`dmstat "${header}_src.pi[channel=${coschannel}][cols counts]" | grep "sum:" | awk '{printf("%f",$2)}'`
bkg_cts=`dmstat "${header}.pi[channel=${coschannel}][cols counts]" | grep "sum:" | awk '{printf("%f",$2)}'`
src_exp=`dmkeypar ${header}_src.pi exposure echo+`
bkg_exp=`echo "scale=10; ${src_exp} * ${bkg_cts} / ${src_cts}" | bc -l`
dmhedit ${header}.pi fi="" op=add ke=exposure va=${bkg_exp}

dmhedit ${header}_src.pi fi="" op=add ke=backfile va=${header}.pi

#rm *${obsid}*fits
rm *.lis

#END