undef("get_shear")
function get_shear (f:file,suffix:string)
local utop, vtop
begin
	; Last 3 chars of suffix define top of shear layer.
	print("get_shear:suffix="+suffix)
	utop = "uzonal_"+str_get_cols(suffix,-3,-1)
	vtop = "umeridional_"+str_get_cols(suffix,-3,-1)
	print("get_shear:utop/vtop="+utop+"/"+vtop)
	; Bottom of shear layer is 10m.
	u = f->$utop$ - f->uzonal_surface
	v = f->$vtop$ - f->umeridional_surface
	speed = sqrt(u^2.+v^2.)
	copy_VarCoords(f->uzonal_surface, speed)
	speed@long_name = suffix + " wind shear"
	speed@units = "m s~S~-1~N~"
	return(speed)
end

undef("get_thickness")
function get_thickness (f:file, fieldname:string, ff:file)
; INPUT
; f : file variable with height field
; fieldname : string starting with "thickness_" and ending with
;               bottom and top of thickness layer.
;             For example, "thickness_1000_500hPa" with bottom
;             separated from top by underscore, ending with "hPA"
; ff : file variable with latCell field


local nTimes, nCells, i, bot, top, fbot, btop, bot_fixed, top_fixed, r2d, xlat, ds, top_string, bot_string, top_fixed, bot_fixed
begin
	if(str_get_cols(fieldname,0,9).ne."thickness_".or.str_get_cols(fieldname,-3,-1).ne."hPa")then
		print("in derived_fields.ncl/get_thickness")
		print("unexpected fieldname:"+fieldname)
		exit
	end if
	; Assumes fieldname is a string like "1000_500hPa"
	; where 1000 is the bottom pressure level and 500 is the top.
	; Find last index of where underscore is found in fieldname
	i = str_index_of_substr(fieldname,"_",-1)
    ; Sanity check
    if (i.lt.11) then
        print("Unexpected thickness fieldname "+fieldname)
        print("Bottom and top pressure levels must be separated by an underscore not a dash.")
        exit
    end if
	bot_string = str_get_cols(fieldname, 10, i-1)
	top_string = str_get_cols(fieldname, i+1, str_index_of_substr(fieldname,"hPa",-1)-1)
	print("get_thickness:bot/top="+bot_string+"/"+top_string)

	if(.not.isfilevar(ff, "latCell"))then
		print("in derived_fields.ncl/get_thickness")
		print("No latitude variable found. Need init.nc?")
		print(ff)
		exit
	end if
	r2d = 180.0/(atan(1)*4.0) ; convert from radians to degrees (float needed for compute_geopotential_height() function)
	xlat = ff->latCell * r2d

	; Use ~ahijevyc/src/ncl_shared_objects/compute_geopotential_height.so

	; convert bottom pressure level geometric height to geopotential height
	fbot = "height_"+bot_string+"hPa"
	bot := f->$fbot$
	ds = dimsizes(bot)
	nTimes = ds(0)
	nCells = ds(1)
	if(num(.not.ismissing(xlat)).ne.num(.not.ismissing(bot)))then
		print("Shape of latitude array doesn't match geometric height")
		exit
	end if
	bot_fixed = bot
	compute_geopotential_height(nTimes, nCells, bot, xlat, bot_fixed)


	; convert top pressure level geometric height to geopotential height
	ftop = "height_"+top_string+"hPa"
	top := f->$ftop$
	top_fixed = top
	compute_geopotential_height(nTimes, nCells, top, xlat, top_fixed)

	thickness = top_fixed - bot_fixed
	copy_VarCoords(top, thickness)
	thickness@long_name = bot_string + "-" + top_string +"hPa thickness"
	if(.not.isatt(thickness, "units"))then
		thickness@units = "m"
	end if
	return(thickness)
end


undef("get_div")
function get_div (f:file,suffix:string)
begin
	uname = "uzonal_"+suffix
	vname = "umeridional_"+suffix
	if (suffix .eq. "10m") then
		uname = "u10"
		vname = "v10"
	end if
	if (suffix .eq. "" .and. isfilevar(f,"ugrd")) then
		uname = "ugrd"
		vname = "vgrd"
	end if
	if (isfilevar(f,"UGRD_P0_L100_GLL0")) then
		uname = "UGRD_P0_L100_GLL0"
		vname = "VGRD_P0_L100_GLL0"
	end if
	u = f->$uname$
	v = f->$vname$
	div = uv2dvF_Wrap(u,v)
	return(div)
end

undef("get_speed")
function get_speed (f:file,suffix:string)
begin
	uname = "uzonal_"+suffix
	vname = "umeridional_"+suffix
	if (suffix .eq. "10m") then
		uname = "u10"
		vname = "v10"
	end if
	if (suffix .eq. "" .and. isfilevar(f,"ugrd")) then
		uname = "ugrd"
		vname = "vgrd"
	end if
	if (isfilevar(f,"UGRD_P0_L100_GLL0")) then
		uname = "UGRD_P0_L100_GLL0"
		vname = "VGRD_P0_L100_GLL0"
	end if
    if (any(.not.isfilevar(f,(/uname,vname/)))) then
        if (all(isfilevar(f,(/"windx","windy"/)))) then
            uname = "windx"
            vname = "windy"
        end if
    end if
	u = f->$uname$
	v = f->$vname$
	speed = sqrt(u^2.+v^2.)
	copy_VarMeta(u, speed)
	speed@long_name = suffix +" wind speed" ; these override res@gsnLeftString
	speed@units = "m s~S~-1~N~"
	return(speed)
end

undef("mseK")
function mseK(heightm:numeric, mixing_ratiokgkg:numeric, temperatureK:numeric)
begin
	Lv = 2.5e06
	cpd = 1004.
	g = 9.81
	mse = cpd*temperatureK + g*heightm + Lv*mixing_ratiokgkg
	mse = mse/cpd ; divide by Cpd to get units of K
	copy_VarCoords(heightm,mse)
	mse@long_name = "moist static energy / Cp"
	mse@units = "K"
	return(mse)
end

undef("thetae")
function thetae(thetaK:numeric, mixing_ratiokgkg:numeric, temperatureK:numeric)
begin
	Lv = 2.5e06
	cpd = 1004.
	theta = thetaK
	r = mixing_ratiokgkg
	theta_e = theta
	if(any(temperatureK.eq.0))then
        ; If there are any zero-Kelvin temperatures, set to missing.
        temperatureK = where(temperatureK.eq.0,getVarFillValue(temperatureK),temperatureK)
    end if
	theta_e = theta * exp(Lv*r/cpd/temperatureK)
	copy_VarCoords(temperatureK,theta_e)
	theta_e@long_name = "Equivalent potential temperature"
    if(isatt(r, "long_name"))then
        if(.not.ismissing(str_index_of_substr(r@long_name,"specific humidity",1)))then
            print("derived_fields.ncl:thetae: expects mixing ratio not specific humidity. proceeding anyway")
        end if
    end if 
	theta_e@units = "K"
	return(theta_e)
end

undef("newfile_dt")
function newfile_dt(f:file,inpath:string,dt:numeric)
begin
	path=inpath

	; for files like f004.nc or 2015-2014.f004.nc
	tmp := systemfunc("basename "+path)
	ifstr = str_index_of_substr(tmp, "f",-1)
	if(.not.ismissing(ifstr))then
		if(str_get_cols(tmp,-3,-1).eq.".nc")then
			; find 3 forecast hour digits
			hour := toint(str_get_cols(tmp,ifstr+1,ifstr+3))
			newfile = systemfunc("dirname "+path)+"/f"+sprintf("%03.0f",hour+dt)+".nc"
			return(newfile)
		end if
	end if

	; for diag* files.
	utc_date = f->xtime(0,:)
	year   := stringtointeger(chartostring(utc_date(0:3)))
	month  := stringtointeger(chartostring(utc_date(5:6)))
	day    := stringtointeger(chartostring(utc_date(8:9)))
	hour   := stringtointeger(chartostring(utc_date(11:12)))
	minute := stringtointeger(chartostring(utc_date(14:15)))
	second := stringtointeger(chartostring(utc_date(17:18)))
	date   := cd_inv_calendar(year,month,day,hour,minute,second,"hours since 1970-01-01 00:00:00",0)
	newdate=date
	newdate = newdate +dt
	utc_date2 = cd_calendar(newdate, 0)
	year2   = tointeger(utc_date2(:,0))
	month2  = tointeger(utc_date2(:,1))
	day2    = tointeger(utc_date2(:,2))
	hour2   = tointeger(utc_date2(:,3))
	minute2 = tointeger(utc_date2(:,4))
	second2 = tointeger(utc_date2(:,5))
	; get prefix for diagnostic file "diag" or "diagnostics"
	diag_str = systemfunc("basename "+path)
	; don't look for year2 in addition to '.' period. Could straddle new year. If anything look for .year
	; if you just look for '.' period the diagnostic prefix string can't have a period '.'
	diag_str = str_get_cols(diag_str,0,str_index_of_substr(diag_str,".",1)-1)
	path = systemfunc("dirname "+path)
	newfile=path+"/"+diag_str+sprinti(".%0.4i-",year2)+sprinti("%0.2i-",month2)+sprinti("%0.2i_",day2)+ \
		sprinti("%0.2i.",hour2)+sprinti("%0.2i.",minute2)+sprinti("%0.2i",second2)+".nc"
	return(newfile)
end

undef("change_in_last_nhours")
function change_in_last_nhours(f:file,inpath:string,infield:string,indt:numeric)
; inpath is the absolute path of the file f.
; Assumes xtime is a char variable like "2013-08-01_00:00:00    "
; Assumes file name like inpath+"/diag*2013-08-01_00.00.00.nc"
begin
	path = inpath
	dt = indt
	var = f->$infield$
	;printVarSummary(var)
	newfile = newfile_dt(f,path,dt)
	if (isfilepresent(newfile))
		tmp := addfile(newfile,"r")
		tmpv := tmp->$infield$
		;print("subtracting "+newfile+" from "+inpath)
		var = var - tmpv
		copy_VarMeta(tmpv,var)
	else
		print("derived_fields.ncl::change_in_last_nhours: no newfile "+newfile+" present")
	end if
	return(var)

end


undef("get_rain")
function get_rain(f:file,inpath:string,dt:numeric)
; Return total precipitation (rainnc + rainc) from a file that is offset dt hours from given file f.
begin
	path = inpath
	if(dt.gt.0)then
		print("get_rain: usually dt is a negative time offset. Are you sure you want a positive dt?")
	end if
	rainnc = change_in_last_nhours(f,path,"rainnc",dt)
	rainc = change_in_last_nhours(f,path,"rainc",dt)
	rain = rainnc + rainc
	copy_VarCoords(rainc,rain)
	rain@long_name = "Precipitation over last "+sprintf("%.0f h",-dt)
	rain@units = "mm"
	if(.not.isatt(rain,"_FillValue"))then
		rain@_FillValue = default_fillvalue(typeof(rain))
	end if
	return(rain)
end

undef("max_over_last_nhours")
function max_over_last_nhours(f:file,inpath:string,infield:string,indt:numeric)
begin
	path = inpath
	field = f->$infield$
	; loop through minus the indt hours (plus one) to -1 hours.
	do dt = -indt+1,-1 
		newfile = newfile_dt(f,path,dt)
		if (isfilepresent(newfile))
			tmp = addfile(newfile,"r")
			tmpv = tmp->$infield$
			field = dim_max_n((/ field, tmpv /),0)	
			delete(tmp)
			delete(tmpv)
		end if
	end do
	return(field)

end


undef("unpack")
function unpack (x:numeric,res)
begin
	; Apply scale_factor
	if (isatt(res,"scale_factor")) then
		x = x / res@scale_factor
		delete(res@scale_factor) ; delete to avoid "not a valid resource" warning
	end if

	; Apply add_offset 
	if (isatt(res,"add_offset")) then
		x = x + res@add_offset
		delete(res@add_offset)
	end if

	; Apply K to F
	if (isatt(res,"convertKtoF")) then
		if (res@convertKtoF) then
			x = (x - 273.15) * 9./5. + 32.
		end if
		delete(res@convertKtoF)
	end if

	return(x)
end

