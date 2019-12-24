#!/usr/bin/env isis-script

require("findzo");
variable x,y;
(x,y)=findzo("acis_evt1.fits","h");
fp=fopen("X0h.par","w");
fprintf (fp,"%f",x);
fclose(fp);
fp=fopen("Y0h.par","w");
fprintf (fp,"%f",y);
fclose(fp);

(x,y)=findzo("acis_evt1.fits","m");
fp=fopen("X0m.par","w");
fprintf (fp,"%f",x);
fclose(fp);
fp=fopen("Y0m.par","w");
fprintf (fp,"%f",y);
fclose(fp);
exit;
