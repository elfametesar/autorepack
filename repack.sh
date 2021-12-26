#!/bin/sh

export PATH=$PWD/bin:$PATH
export LC_ALL=C
export TERM=linux
export TERMINFO=$PREFIX/share/terminfo/
mkdir -p /sdcard/Repacks
HOME=$PWD

trap "jobs -p | xargs kill &> /dev/null" SIGTERM

integrity_check(){
    headcount=0
    if [ ! -e extracted/*.img &> /dev/null ]; then sh cleanup.sh; return; fi
    for check in $(ls extracted/*.img | xargs -n1 basename)
    do
        case "$check" in (system.img|product.img|system_ext.img|boot.img|vendor_boot.img|dtbo.img)
           let "headcount+=1"
        esac
    done
    if [ ! "$headcount" == 6 ]; then
        dialog --title "Integrity Check" --msgbox "There are some useless leftover .img files in the workspace. They will be cleaned up." 6 50
        sh cleanup.sh &> /dev/null
    else
        dialog --yesno "You already have some extracted img files in workspace. Do you want to continue with them?" 6 50
        if [ "$?" == "0" ]; then ui_menu; rom_dialog; select_mod; start_repack; else sh cleanup.sh; return; fi
    fi
}

ui_menu(){
    [ ! -f ".conf" ] && menu
    [ ! -f ".conf" ] && exit
    opts=$(tr -d "[]" < .conf | sed 's/None//')
    file=$(sed -n 1p <<< $opts)
    name=$(echo "$(sed -n 2p <<< $opts)" | sed 's/\.[^.]*$//')
    ROMTYPE=$(sed -n 3p <<< $opts)
    fw=$(sed -n 4p <<< $opts)
    rw=$(sed -n 5p <<< $opts)
    comp_level=$(sed -n 6p <<< $opts)
    mm=$(sed -n 7p <<< $opts)
    [ $mm -eq 1 ] && magisk=$(sed -n 8p <<< $opts) 
    addons=$(sed -n 9p <<< $opts)
}

successbar(){
    (
    while [[ ! ${current%\.*} -eq 100 ]];
     do
     curfile=$(ls -tc $extractTo | head -n 1)
     chunk=$(du -sb $extractTo | awk '{print $1}')
     current=$(bc -l <<< $chunk/$fullsize*100)
     echo ${current%\.*}
     echo "XXX"
     echo "‎"
     echo "Files are extracting: $curfile"
     echo "XXX"
     sleep 1
     done
     ) |
     dialog  --title "$type" --gauge "" 7 70 0
}

payload_extract(){
    extractTo="extracted/"
    fullsize=$(paydump -l $file $extractTo | tail -1)
    sleep 3
    type="Payload Image Extraction"
    current=0.0
    paydump -c 8 -o $extractTo $file &> /dev/null &
    successbar
    rm tmp/*
    if [ ! -z "$fw" ]; then
        unzip -l "$fw" | grep -q .img;
        if [ $? == 0 ]; then
            extractTo="tmp/"
            fullsize=$(7za l "$fw" *.img -r | awk 'END{ print $3 }')
            type="Firmware Extraction"
            current=0.0
            7za e -o$extractTo "$fw" *.img -r -y &> /dev/null &
            successbar
            wait
        fi
        mv tmp/* extracted/
    fi
}

fastboot_extract(){
    type="Fastboot Image Extraction"
    extractTo="tmp/"
    current=0.0
    if [[ "$file" == *.tgz ]]; then
        echo "\e[37mRetrieving information from archive...\e[0m"
        fullsize=$(7za e -so "$file" -mmt8 | 7za l -si -ttar *.img -r -mmt8 | awk 'END{ print $4 }')
        7za e -so "$file" -mmt8 | 7za e -si -ttar *.img -r -mmt8 -o$extractTo &> /dev/null &
        successbar &
        wait
    else
        fullsize=$(7za l "$file" *.img -r | grep "files" | awk '{ print $3 }') 
        7za e "$file" -o$extractTo *.img -y -r -mmt8 &> /dev/null &
        successbar &
        wait
    fi
    echo
    file tmp/super.img | grep -q sparse
    if [[ "$?" == "0" ]]; then
        echo -e "\e[37mConverting super.img to raw...\e[0m"
        simg2img tmp/super.img extracted/super.img
        rm tmp/super.img
    else
        mv tmp/super.img extracted/
    fi
    mv tmp/* extracted/
    echo -e "\e[37mUnpacking super...\e[0m"
    lpunpack --slot=0 extracted/super.img extracted/
    rm extracted/super.img
    for file in extracted/*_a.img ; do
        mv $file extracted/$(basename $file _a.img).img
    done
    rm -rf tmp/*
    rm -rf extracted/*_b.img
    rm extracted/rescue.img extracted/userdata.img extracted/dummy.img extracted/persist.img extracted/metadata.img extracted/metadata.img &> /dev/null
    if [ ! -z "$fw" ]; then
        unzip -l "$fw" | grep -q .img;
        if [ $? == 0 ]; then
            extractTo="tmp/"
            fullsize=$(7za l "$fw" *.img -r | awk 'END{ print $3 }')
            type="Firmware Extraction"
            current=0.0
            7za e -o$extractTo "$fw" *.img -r -y &> /dev/null &
            successbar
            wait
        fi
        mv tmp/* extracted/
    fi
}


filepicker(){
    if [[ "$file" == *.tgz ]]; then
        rom_dialog
        select_mod
        fastboot_extract
    elif [[ "$file" == *.zip ]]; then
        unzip -l "$file" | grep -q payload.bin;
        if [ "$?" == "0" ]; then
            rom_dialog
            select_mod
            extractTo="tmp/"
            fullsize=$(7za l "$file" *.bin | awk 'END{ print $4 }')
            type="Payload.bin Extraction"
            current=0.0
            7za e -o$extractTo "$file" payload.bin -y -mmt8 &> /dev/null &
            successbar
            file=tmp/payload.bin
            payload_extract
        else
            7za l "$file" super.img -r | grep -q "$super.img$"
            if [ "$?" == "0" ]; then
                rom_dialog
                select_mod
                fastboot_extract
            else
                echo -e "\e[1;31mYou did not choose a valid file.\e[0m"
                sleep 1
                exit
            fi
        fi
    elif [[ "$file" == *.7z ]]; then
        7za l "$file" super.img -r | grep -q $super.img$
        if [ "$?" == "0" ]; then
            payload=$file
            rom_dialog
            select_mod
            fastboot_extract
        else
            echo -e "\e[1;31mYou did not choose a valid file.\e[0m"
            sleep 1
            exit
        fi
    elif [[ "$file" == *.bin ]]; then
        payload=$file
        rom_dialog
        select_mod
        payload_extract
    else
        echo -e "\e[1;31mYou did not choose a valid file.\e[0m"
        sleep 1
        exit
    fi
    start_repack
}


start_repack(){
     case "$mod" in
      "123")
      make_rw
      vendor_patch
      get_image_size
      img_to_sparse
      magisk_recovery_patch
      get_image_size
      final_act
      ;;
      "13")
      make_rw
      vendor_patch
      get_image_size
      img_to_sparse
      magisk_patch
      get_image_size
      final_act
      ;;
      "12")
      make_rw
      get_image_size
      img_to_sparse
      magisk_recovery_patch
      get_image_size
      final_act
      ;;
      "23")
      make_rw
      vendor_patch
      get_image_size
      img_to_sparse
      recovery_patch
      get_image_size
      final_act
      ;;
      "2")
      make_rw
      get_image_size
      img_to_sparse
      recovery_patch
      get_image_size
      final_act
      ;;
      "3")
      make_rw
      vendor_patch
      ln -n extracted/boot.img $OUTFW""boot/boot.img
      get_image_size
      img_to_sparse
      get_image_size
      final_act
      ;;
      "1")
      make_rw
      get_image_size
      img_to_sparse
      magisk_patch
      get_image_size
      final_act
      ;;
      "")
      make_rw
      get_image_size
      ln -n extracted/boot.img $OUTFW""boot/boot.img
      img_to_sparse
      get_image_size
      final_act
      ;;
     esac
}

rom_dialog(){
    case "$ROMTYPE" in
     "0")
    OUT="./output/AOSP/"
    OUTFW="./output/AOSP/"
    mkdir -p $OUT
    ;;
    "1")
    OUT="./output/MIUI/rom/"
    OUTFW="./output/MIUI/fw/"
    mkdir -p $OUT $OUTFW
    comp_level=3
    ;;
    esac
    rom_updater_path="$OUT""META-INF/com/google/android"
    fw_updater_path="$OUTFW""META-INF/com/google/android"
    mkdir -p $OUTFW""boot $rom_updater_path
    mkdir -p $fw_updater_path $OUTFW""firmware-update $OUTFW""boot

}

magisk_choose_dialog(){
    [ -z "$magisk" ] && return
    unzip -l "$magisk" | grep -q lib/arm64-v8a/libmagiskboot.so
    [ "$?" == 0 ] && arch="arm64-v8a" || arch="armeabi-v7a"
    rm -rf .magisk && mkdir .magisk
    unzip -p "$magisk" lib/$arch/libmagiskboot.so > .magisk/magiskboot
    unzip -p "$magisk" lib/$arch/libbusybox.so > .magisk/busybox
    unzip -p "$magisk" lib/$arch/libmagisk64.so > .magisk/magisk64
    unzip -p "$magisk" lib/$arch/libmagiskinit.so > .magisk/magiskinit
    unzip -p "$magisk" assets/boot_patch.sh > .magisk/boot_patch.sh
    unzip -p "$magisk" assets/util_functions.sh > .magisk/util_functions.sh
    mkdir .magisk/chromeos
    unzip -j -qq "$magisk" assets/chromeos/* -d .magisk/chromeos/
    chmod -R +x .magisk
}

select_mod(){ 
    grep -q 'Magisk' <<< $addons
    [ "$?" == 0 ] && mod+="1"
    grep -q 'Recovery' <<< $addons
    [ "$?" == 0 ] && mod+="2"
    grep -q 'DFE' <<< $addons
    [ "$?" == 0 ] && mod+="3"
    case "$mod" in
      "123")
      magisk_choose_dialog
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_Magisk+TWRP+DFE_repack"
      ;;
      "13")
      magisk_choose_dialog
      nameext="_Magisk+DFE_repack"
      ;;
      "12")
      magisk_choose_dialog
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_Magisk+TWRP_repack"
      ;;
      "23")
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_TWRP+DFE_repack"
      ;;
      "2")
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_TWRP_only_repack"
      ;;
      "3")
      nameext="_DFE_only_repack"
      ;;
      "1")
      magisk_choose_dialog
      nameext="_Magisk_only_repack"
      ;;
      "")
      nameext="_only_repack"
      ;;
    esac
}

magisk_recovery_patch(){
    recovery_patch
    echo -e "\e[32m Patching kernel with Magisk...\e[0m"
    [ ! -d ".magisk" ] && cp -rf /data/adb/magisk/ .magisk
    magiskpath=".magisk"
    mv -f $OUTFW""boot/boot.img $magiskpath/
    sh $magiskpath/boot_patch.sh boot.img &> /dev/null
    rm $magiskpath/boot.img
    mv $magiskpath/new-boot.img $OUTFW""boot/boot.img
    rm -rf .magisk
    echo -e "\e[1;32m Magisk patch is done.\e[0m"
}

magisk_patch(){
    echo -e "\e[32m Patching kernel with Magisk...\e[0m"
    [ ! -d ".magisk" ] && cp -rf /data/adb/magisk/ .magisk
    magiskpath=".magisk"
    ln -n extracted/boot.img $magiskpath/
    sh $magiskpath/boot_patch.sh boot.img &> /dev/null
    rm $magiskpath/boot.img
    mv $magiskpath/new-boot.img $OUTFW""boot/boot.img
    rm -rf .magisk
    echo -e "\e[1;32m Magisk patch is done.\e[0m"
}

recovery_patch(){
    echo -e "\e[32m Patching kernel with TWRP...\e[0m"
    [ ! -d ".magisk" ] && cp -rf /data/adb/magisk/ .magisk
    ln -n extracted/boot.img .magisk/
    cd .magisk
    ./magiskboot unpack boot.img &> /dev/null
    tar xf ../twrp/"$twrp" -C ./
    ./magiskboot cpio ramdisk.cpio sha1 &> /dev/null
    ./magiskboot repack boot.img &> /dev/null
    cd ..
    mv .magisk/new-boot.img $OUTFW""boot/boot.img
    .magisk/magiskboot cleanup &> /dev/null
    echo -e "\e[1;32m Recovery patch is done.\e[0m"
}

get_image_size(){
    VENDOR="$(stat -c%s extracted/vendor.img | cut -f1)"
    SYSTEM="$(stat -c%s extracted/system.img | cut -f1)"
    SYSTEMEXT="$(stat -c%s extracted/system_ext.img | cut -f1)"
    PRODUCT="$(stat -c%s extracted/product.img | cut -f1)"
    if [ ! -z "$(ls extracted | grep odm.img)" ]; then
        ODM="$(stat -c%s extracted/odm.img | cut -f1)"
    else
        ODM=0
    fi
    total=`awk 'BEGIN{ print '$VENDOR'+'$SYSTEM'+'$SYSTEMEXT'+'$PRODUCT'+'$ODM' }'`
}

vendor_patch(){
    tune2fs -f -O ^read-only extracted/vendor.img &> /dev/null
    echo -e "\e[1m\e[37m Mounting vendor.img... \e[0m"
    umount tmp &> /dev/null
    count=0
    while [ $count -le 5 ]; do
        let "count++"
        mount extracted/vendor.img tmp/ &> /dev/null
        mountpoint -q tmp/
        [ "$?" == "0" ] && break
    done
    mountpoint -q tmp/
    if [ "$?" == "0" ]; then
        echo -e "\e[1;32m Vendor image has temporarily been mounted.\e[0m"
        sh dfe.sh tmp/ &> /dev/null
        sh dfe.sh tmp/ 
        sed -i 's/encrypted/unsupported/' tmp/etc/init/hw/init.gourami.rc &> /dev/null
        umount tmp
    else
        echo -e "\e[1;31m Vendor image could not be mounted. Continuing without DFE patch.\e[0m"
    fi
    if [ $rw == 0 ]; then
        tune2fs -f -O read-only extracted/vendor.img &> /dev/null
    fi
}

make_rw(){
    [ "$rw" == "0" ] && return
    echo -e "\e[1m\e[37mGiving read and write permissions...\e[0m"
    for img in extracted/*img; do
        case "$(basename $img /)" in
         (system.img|system_ext.img|vendor.img|product.img|odm.img)
          tune2fs -l $img | grep -q 'shared_blocks'
          [ "$?" == 1 ] && continue
          new_size=$(du -sb $img | awk '{ print $1/4096+48829 }')
          resize2fs $img $new_size &> /dev/null
          e2fsck -y -E unshare_blocks $img &> /dev/null
          e2fsck -fy $img &> /dev/null
          resize2fs -M $img &> /dev/null
         esac
    done
}

multi_process(){
    img2simg extracted/$file $OUT""$file 4096
    img2sdat $OUT""$file -v4 -o $OUT -p ${file%.*} &> /dev/null  
    rm $OUT""$file 2> /dev/null && \
    [ $comp_level -gt 0 ] && \
        brotli -$comp_level -j $OUT""${file%.*}.new.dat
}

img_to_sparse(){
    echo
    echo -e "\e[1;32m Converting images in background\e[0m" 
    increment=`awk 'BEGIN{ print 9126805504-'$total' }'`
    for file in $(ls -1 extracted | grep .img)
    do
        if ! case "$file" in (system.img|product.img|system_ext.img|odm.img|vendor.img) false; esac; then
            if [ "$file" == "system.img" ]; then
                fallocate -l `echo $increment/2 | bc` extracted/$file
                resize2fs extracted/$file &> /dev/null
            else
                fallocate -l `echo $increment/2/4 | bc` extracted/$file
                resize2fs extracted/$file &> /dev/null 
            fi
            multi_process &
            continue
        fi
        if ! case "$file" in (vendor_boot.img|dtbo.img) false; esac; then
            if [ "$ROMTYPE" == "1" ]; then 
                ln extracted/$file $OUTFW"boot/"
                continue
            else
                ln extracted/$file $OUT"boot/"
                continue
            fi
        fi
        if [ $file == "boot.img" ]; then
            continue
        fi
        ln -n extracted/$file $OUTFW"firmware-update/"
    done
    echo
}

create_zip_structure(){
    [ -z "$name" ] && name="UnnamedRom"
    echo -e "ui_print(\"*****************************\");\n" \
                 "ui_print(\" - $name by AutoRepack\");\n" \
                 "ui_print(\"*****************************\");\n\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_root\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/product\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_ext\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/odm\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/vendor\");\n" \
                 "ui_print(\"Flashing partition images...\");\n" | sed 's/^ *//g' >> $fw_updater_path/updater-script
    for fw in $(ls $OUTFW""firmware-update/ $OUTFW""boot/ | grep .img); do
        if ! case "$fw" in (boot.img|vendor_boot.img|dtbo.img) false; esac; then
            root="boot"
        else
            root="firmware-update"
        fi
        echo -e "package_extract_file(\"$root/$fw\", \"/dev/block/bootdevice/by-name/$(basename $fw .img)_a\");" >> $fw_updater_path/updater-script
        echo -e "package_extract_file(\"$root/$fw\", \"/dev/block/bootdevice/by-name/$(basename $fw .img)_b\");\n" >> $fw_updater_path/updater-script
    done
    case $ROMTYPE in 
     1)
        mv output/MIUI/rom/vendor* $OUTFW
        echo -e "\nassert(update_dynamic_partitions(package_extract_file(\"dynamic_partitions_op_list\")));\n" >> $fw_updater_path/updater-script
        echo -e "ui_print(\"Flashing vendor_a partition...\");" >> $fw_updater_path/updater-script
        echo -e "block_image_update(map_partition(\"vendor_a\"), package_extract_file(\"vendor.transfer.list\"), \"vendor.new.dat.br\", \"vendor.patch.dat\") ||" \
        "abort(\"E2001: Failed to flash vendor_a partition.\");\n\n" >> $fw_updater_path/updater-script
        echo -e "show_progress(0.100000, 10);\n" \
                 "run_program(\"/system/bin/bootctl\", \"set-active-boot-slot\", \"0\");\n" \
                 "set_progress(1.000000);" | sed 's/^ *//g' >> $fw_updater_path/updater-script
        echo -e "ui_print(\"*****************************\");\n" \
                 "ui_print(\" - $name by AutoRepack\");\n" \
                 "ui_print(\"*****************************\");\n\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_root\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/product\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_ext\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/odm\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/vendor\");\n" \
                 "ui_print(\"Flashing partition images...\");\n" | sed 's/^ *//g' >> $rom_updater_path/updater-script
        ln -n bin/aarch64-linux-gnu/update-binary $fw_updater_path
     ;;
    esac
    ln -n bin/aarch64-linux-gnu/update-binary $rom_updater_path
    echo -e "assert(update_dynamic_partitions(package_extract_file(\"dynamic_partitions_op_list\")));\n" >> $rom_updater_path/updater-script
    for partition in $(ls $OUT | grep .new.dat); do
        echo -e "ui_print(\"Flashing $(echo $partition | cut -d. -f1)_a partition...\");\n" \
        "show_progress(0.100000, 0);\n" \
        "block_image_update(map_partition(\"$(echo $partition | cut -d. -f1)_a\"), package_extract_file(\"$(echo $partition | cut -d. -f1).transfer.list\"), \"$partition\", \"$(echo $partition | cut -d. -f1).patch.dat\") ||" \
        "abort(\"E2001: Failed to flash $(echo $partition | cut -d. -f1)_a partition.\");\n" | sed 's/^ *//g' >> $rom_updater_path/updater-script
    done
    echo -e "\nshow_progress(0.100000, 10);\n" \
             "run_program(\"/system/bin/bootctl\", \"set-active-boot-slot\", \"0\");\n" \
             "set_progress(1.000000);" | sed 's/^ *//g' >> $rom_updater_path/updater-script
    echo
    echo -e "\e[1m\e[37mAdding img sizes in dynamic partition list...\e[0m"
    echo -e "remove_all_groups\n" \
          "add_group qti_dynamic_partitions_a 9122611200\n" \
          "add_group qti_dynamic_partitions_b 9122611200\n" \
          "add system_a qti_dynamic_partitions_a\n" \
          "add system_b qti_dynamic_partitions_b\n" \
          "add system_ext_a qti_dynamic_partitions_a\n" \
          "add system_ext_b qti_dynamic_partitions_b\n" \
          "add product_a qti_dynamic_partitions_a\n" \
          "add product_b qti_dynamic_partitions_b\n" \
          "add vendor_a qti_dynamic_partitions_a\n" \
          "add vendor_b qti_dynamic_partitions_b\n" \
          "add odm_a qti_dynamic_partitions_a\n" \
          "add odm_b qti_dynamic_partitions_b\n" \
          "resize system_a $SYSTEM\n" \
          "resize system_ext_a $SYSTEMEXT\n" \
          "resize product_a $PRODUCT" | sed 's/^ *//g' >>$OUT"dynamic_partitions_op_list"
    case $ROMTYPE in
     1)
      echo -e "remove vendor_a\n" \
              "remove vendor_b\n" \
              "add vendor_a qti_dynamic_partitions_a\n" \
              "add vendor_b qti_dynamic_partitions_b\n" \
              "resize vendor_a $VENDOR" | sed 's/^ *//g' >>$OUTFW"dynamic_partitions_op_list"
     ;;
     0)
      echo -e "resize vendor_a $VENDOR" >>$OUT"dynamic_partitions_op_list"
     ;;
    esac
    if [ ! -z "$(ls extracted | grep odm.img)" ]; then
      echo -e "resize odm_a $ODM" >>$OUT"dynamic_partitions_op_list"
    fi
}

final_act(){
    echo
    echo -e "\e[32m Waiting for image processes to be done\e[0m"
    wait
    create_zip_structure
    echo
    echo -e "\e[32m -------------------------------------------------------\e[0m"
    echo -e "\e[32m            Creating flashable repack rom.\e[0m"
    echo -e "\e[32m -------------------------------------------------------\e[0m"
    echo
    if [ $ROMTYPE == "1" ]; then
        echo
        echo -e "\e[1m\e[37mPacking MIUI firmware files...\e[0m"
        echo
        cd output/MIUI/fw
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext"-Step2.zip * -bso0
        echo
        echo -e "\e[1m\e[37mPacking MIUI rom files...\e[0m"
        echo
        cd ../rom
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext"-Step1.zip * -bso0
    else
        echo -e "\e[1m\e[37mPacking rom files...\e[0m"
        echo
        cd $OUT
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext".zip * -bso0
    fi
    cd $HOME
    sh cleanup.sh &> /dev/null
    echo -e "\e[1;32mYour repacked rom is ready to flash. You can find it in /sdcard/Repacks/ \e[0m"
    exit
}

rm -rf tmp/* output .magisk
integrity_check
ui_menu
filepicker
