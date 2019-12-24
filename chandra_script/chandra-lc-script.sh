#!/bin/bash


cd $OBSID #观测id目录


heainit
ciao

mkdir cal_zcor
cd cal_zcor
export MAINDIR=".."


# untar events file and get some link in cal directory
find $MAINDIR -name '*evt1*.fits.gz' -exec gunzip {} \;
#find $MAINDIR -name '*evt1*' -exec ln -s {} acis_evt1.fits \;
find $MAINDIR -name '*evt1*' -exec cp {} acis_evt1.fits \;

echo CALDBVER=$(dmkeypar acis_evt1.fits CALDBVER echo+)

echo CALDBVER=$(dmkeypar acis_evt1.fits ASCDSVER echo+)

#  Detect and centroid the zero order image in a spatial sub-region of a grating event list.
punlearn tgdetect
tgdetect infile=acis_evt1.fits outfile=acis_src1a.fits OBI_srclist_file=NONE

# need calculate positions for the cross point of two arms to corrrect the position of 0 order
# use isis script "findzo"
cp ~/zeropoint.sl .  #这下面几步用到isis的脚本修正零级位置，我写成自动的了。可以手动操作
chmod 755 zeropoint.sl
./zeropoint.sl



#######################################################
#                          HEG  
#####################################################
X0=$(cat X0h.par)
Y0=$(cat Y0h.par)

fpartab $X0 "acis_src1a.fits[1]" x 1
fpartab $Y0 "acis_src1a.fits[1]" y 1






#
# Create a region file to define spectrum sky boundaries
# will be used in tg_resovle_events
#
punlearn tg_create_mask
tg_create_mask infile=acis_evt1.fits outfile=acis_evt1_L1a.fits input_pos_tab=acis_src1a.fits grating_obs=header_value width_factor_hetg=4

#
# Find Aspect Camera Assembly (ACA) offsets file, or Pointing Control and 
# Aspect Determination (PCAD) aspect solution (asol) file.
# put all of them into link, used in tg_resovle_events in the following 
#
find $MAINDIR -name 'pcadf*_asol1.fits.gz' -exec gunzip {} \;
find $MAINDIR -name 'pcadf*_asol1.fits' -exec sh -c 'ls {} >> pcadFile' \;

# check pcadFile:  Aspect files must be arranged in chronological order

#
# Assign grating events to spectral orders; use detector energy resolution 
# for order separation, if available.
#
punlearn tg_resolve_events
tg_resolve_events infile=acis_evt1.fits outfile=acis_evt1a.fits regionfile=acis_evt1_L1a.fits acaofffile=@pcadFile eventdef=")stdlev1_ACIS"

# 
# get good grades
#
punlearn dmcopy
dmcopy "acis_evt1a.fits[EVENTS][grade=0,2,3,4,6,status=0]" acis_flt_evt1a.fits opt=all

#
# find filter files
#
find $MAINDIR -name '*flt*.fits.gz' -exec gunzip {} \;
find $MAINDIR -name 'acis*flt*' -exec ln -s {} fltFile \;
ls -l fltFile

#
# filter the event file again
#
punlearn dmcopy
dmcopy "acis_flt_evt1a.fits[EVENTS][@fltFile][cols -phas]" acis_evt2.fits opt=all


##########################
# new axbary correction
#
##########################
find $MAINDIR -name '*orbit*.fits.gz' -exec gunzip {} \;
find $MAINDIR -name 'orbit*.fits' -exec ln -s {} orbFile \;
ls -l orbFile
axbary acis_evt2.fits  orbFile acis_evt2_orb.fits

#  Remove streak events from ACIS data, normally only for ccd chip 8
punlearn destreak
#destreak infile=acis_evt2.fits outfile=acis_dstrk_evt2.fits ccd_id=8
destreak infile=acis_evt2_orb.fits outfile=acis_dstrk_evt2.fits ccd_id=8



# Bin event list grating wavelengths column into a one-dimensional counts histogram, 
# by source, grating part, and diffraction order.
#
punlearn tgextract
tgextract infile=acis_dstrk_evt2.fits outfile=acis_pha2.fits ancrfile=none respfile=none outfile_type=pha_typeII tg_srcid_list=all tg_part_list=header_value tg_order_list=default

# for bad pix files
find $MAINDIR -name 'acis*bpix1.fits.gz' -exec gunzip {} \;
rm ~/cxcds_param/ardlib.par -f
cd $MAINDIR/primary
acis_set_ardlib *bp*.fits    
cd $MAINDIR/cal_zcor
find $MAINDIR -name 'acis*bpix1.fits' -exec ln -s {} bpFile \;

# newly added file
find $MAINDIR -name 'acis*pbk*.fits.gz' -exec gunzip {} \;
find $MAINDIR -name 'acis*pbk*.fits' -exec ln -s {} pbkFile \;

#
#  Generate an RMF for Chandra grating data
# for HEG and MEG all orders
# "p" is positive arm, "m" is negative arm
#
punlearn mkgrmf
mkgrmf order=1 grating_arm=HEG outfile=heg_p1.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

punlearn mkgrmf
mkgrmf order=2 grating_arm=HEG outfile=heg_p2.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

#punlearn mkgrmf
mkgrmf order=3 grating_arm=HEG outfile=heg_p3.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

punlearn mkgrmf
mkgrmf order=-1 grating_arm=HEG outfile=heg_m1.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

#punlearn mkgrmf
mkgrmf order=-2 grating_arm=HEG outfile=heg_m2.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

#punlearn mkgrmf
mkgrmf order=-3 grating_arm=HEG outfile=heg_m3.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0


# find mask file for the observation, which is used in mkgarf
#
find $MAINDIR -name '*msk1*.fits.gz' -exec gunzip {} \;
find $MAINDIR -name '*msk1*' -exec ln -s {} mskFile \;

#
#Generate a Chandra Grating ARF for one detector element.
#
# it seems that I need to re-longin in order to make it run, is that confict with xspec? weried. 9/7/08
# still the case when I run ciao v4 5/27/09
#

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=3 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(heg_m1.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=2 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(heg_m2.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=1 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(heg_m3.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=4 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(heg_p1.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=5 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(heg_p2.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=6 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(heg_p3.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes



###########################################################
###                           MEG
############################################################

X0=$(cat X0m.par)
Y0=$(cat Y0m.par)


fpartab $X0 "acis_src1a.fits[1]" x 1
fpartab $Y0 "acis_src1a.fits[1]" y 1


#
# Create a region file to define spectrum sky boundaries
# will be used in tg_resovle_events
#
punlearn tg_create_mask
tg_create_mask infile=acis_evt1.fits outfile=acis_evt1_L1a.fits input_pos_tab=acis_src1a.fits grating_obs=header_value width_factor_hetg=4


# Assign grating events to spectral orders; use detector energy resolution 
# for order separation, if available.
#
punlearn tg_resolve_events
tg_resolve_events infile=acis_evt1.fits outfile=acis_evt1a.fits regionfile=acis_evt1_L1a.fits acaofffile=@pcadFile eventdef=")stdlev1_ACIS"

# 
# get good grades
#
punlearn dmcopy
dmcopy "acis_evt1a.fits[EVENTS][grade=0,2,3,4,6,status=0]" acis_flt_evt1a.fits opt=all

#
# filter the event file again
#
punlearn dmcopy
dmcopy "acis_flt_evt1a.fits[EVENTS][@fltFile][cols -phas]" acis_evt2.fits opt=all


##########################
# new axbary correction
#
##########################
axbary acis_evt2.fits  orbFile acis_evt2_orb.fits

#  Remove streak events from ACIS data, normally only for ccd chip 8
punlearn destreak
#destreak infile=acis_evt2.fits outfile=acis_dstrk_evt2.fits ccd_id=8
destreak infile=acis_evt2_orb.fits outfile=acis_dstrk_evt2.fits ccd_id=8



# Bin event list grating wavelengths column into a one-dimensional counts histogram, 
# by source, grating part, and diffraction order.
#
punlearn tgextract
tgextract infile=acis_dstrk_evt2.fits outfile=acis_pha2.fits ancrfile=none respfile=none outfile_type=pha_typeII tg_srcid_list=all tg_part_list=header_value tg_order_list=default



#
#  Generate an RMF for Chandra grating data
# for HEG and MEG all orders
# "p" is positive arm, "m" is negative arm

#punlearn mkgrmf

punlearn mkgrmf
mkgrmf order=1 grating_arm=MEG outfile=meg_p1.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

#punlearn mkgrmf
mkgrmf order=2 grating_arm=MEG outfile=meg_p2.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

punlearn mkgrmf
mkgrmf order=3 grating_arm=MEG outfile=meg_p3.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

punlearn mkgrmf
mkgrmf order=-1 grating_arm=MEG outfile=meg_m1.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

punlearn mkgrmf
mkgrmf order=-2 grating_arm=MEG outfile=meg_m2.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0

punlearn mkgrmf
mkgrmf order=-3 grating_arm=MEG outfile=meg_m3.rmf obsfile="acis_pha2.fits[SPECTRUM]" regionfile=acis_pha2.fits detsubsys=ACIS-S3 wvgrid_arf=compute  wvgrid_chan=compute clobber=no srcid=1 threshold=1e-06 verbose=0


#
#Generate a Chandra Grating ARF for one detector element.
#

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=7 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(meg_m3.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" pbkfile=pbkFile badpix=bpFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=8 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(meg_m2.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=9 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(meg_m1.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=10 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(meg_p1.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=11 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(meg_p2.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes

punlearn fullgarf
fullgarf phafile=acis_pha2.fits pharow=12 evtfile=acis_dstrk_evt2.fits asol=@pcadFile engrid="grid(meg_p3.rmf[cols ENERG_LO,ENERG_HI])" dtffile=")evtfile" badpix=bpFile pbkfile=pbkFile maskfile=mskFile rootname=acis clobber=yes


rm -v zeropoint.sl
cd ../..

done
cd ../..
done


#如果想抽出光变曲线，请参考使用isis脚本，http://space.mit.edu/cxc/analysis/aglc/  ####
