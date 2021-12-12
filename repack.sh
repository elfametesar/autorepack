#!/bin/sh

export PATH=$PWD/bin:$PATH
mkdir -p /sdcard/Repacks

integrity_check(){
    headcount=0
    if [ ! -e extracted/*.img &> /dev/null ]; then return; fi
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
        if [ "$?" == "0" ]; then file_renamer; rom_dialog; select_mod; start_repack; else sh cleanup.sh; return; fi
    fi
}

successbar(){
    (
    while [[ ! ${current%\.*} -eq 100 ]];
     do
     curfile=$(ls $extractTo | tail -1)
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
     dialog  --title "$type" --gauge "" 6 70 0
}

payload_extract(){
    extractTo="extracted/"
    fullsize=$(paydump $file $extractTo True)
    sleep 3
    type="Payload Image Extraction"
    current=0.0
    paydump $file $extractTo &> /dev/null &
    successbar
    rm tmp/*
}

fastboot_extract(){
    type="Fastboot Image Extraction"
    extractTo="tmp/"
    current=0.0
    if [[ "$file" == *.tgz ]]; then
        echo "\e[37mRetrieving information from archive...\e[0m"
        add=0
        list=$(tar tvf $file --wildcards --no-anchored '*.img' | awk '{ print $3 }')
        for size in $list; do add=$(bc -l <<< $add+$size); done
        fullsize=$add
        tar xf $file -C tmp/ -m --wildcards --no-anchored '*.img' --strip-components 2 &
        successbar &
        wait
    else
        fullsize=$(7za l $file *.img -r | grep "files" | awk '{ print $3 }') 
        7za e $file -o$extractTo *.img -y -r &> /dev/null &
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
}

file_renamer(){
    repackrename="$(dialog --stdout --inputbox "Do you want to rename your repack ROM? Leave it blank for default value:" 10 50)"
    dialog --colors --yesno "Do you want to give your repack read and write permissions? If given, ROM will \Z1not boot\Z0 without magisk." 7 50
    if [ $? == 0 ]; then rw=1; else rw=0; fi
}

compression_level(){
    dialog --yesno "Do you want to compress the repack? This will reduce the size but will take longer." 7 50
    if [ "$?" == 0 ]; then
        comp_level=$(dialog --stdout --radiolist "Select compression level:" 17 23 7 $(seq 9 | $PREFIX/bin/xargs -I {} echo {} ‎ 0))
    fi
}

filepicker(){
    file=$(dialog --stdout --title "USE SPACE TO SELECT FILES AND FOLDERS" --fselect /sdcard/ -1 -1)
    if [[ "$file" == *.tgz ]]; then
        repackname="$(basename $file .tgz)"
        rom_dialog
        select_mod
        fastboot_extract
    elif [[ "$file" == *.zip ]]; then
        unzip -l $file | grep -q payload.bin;
        if [ "$?" == "0" ]; then
            repackname="$(basename $file .zip)"
            rom_dialog
            select_mod
            extractTo="tmp/"
            fullsize=$(7za l $file *.bin | tail -n 1 | xargs | cut -d' ' -f3)
            type="Payload.bin Extraction"
            current=0.0
            7za e -o$extractTo $file payload.bin -y &> /dev/null &
            successbar
            file=tmp/payload.bin
            payload_extract
        else
            7za l $file super.img -r | grep -q "$super.img$"
            if [ "$?" == "0" ]; then
                repackname="$(basename $file .zip)"
                rom_dialog
                select_mod
                fastboot_extract
            else
                echo -e "\e[1;31mYou did not choose a valid file.\e[0m"
                sleep 1
            fi
        fi
    elif [[ "$file" == *.7z ]]; then
        7za l $file super.img -r | grep -q $super.img$
        if [ "$?" == "0" ]; then
            repackname="$(basename $file .7z)"
            payload=$file
            rom_dialog
            select_mod
            fastboot_extract
        else
            echo -e "\e[1;31mYou did not choose a valid file.\e[0m"
            sleep 1
        fi
    elif [[ "$file" == *.bin ]]; then
        payload=$file
        rom_dialog
        select_mod
        payload_extract
    else
        echo -e "\e[1;31mYou did not choose a valid file.\e[0m"
        sleep 1
    fi
    start_repack
}

start_repack(){
     case "$mod" in
      "1")
      make_rw
      vendor_patch
      get_image_size
      img_to_sparse
      sparse_to_dat
      magisk_recovery_patch
      create_zip_structure
      final_act
      ;;
      "2")
      make_rw
      vendor_patch
      get_image_size
      img_to_sparse
      sparse_to_dat
      magisk_patch
      create_zip_structure
      final_act
      ;;
      "3")
      make_rw
      get_image_size
      img2simg extracted/vendor.img $OUT""vendor.img 4096
      img_to_sparse
      sparse_to_dat
      magisk_recovery_patch
      create_zip_structure
      final_act
      ;;
      "4")
      make_rw
      vendor_patch
      get_image_size
      img_to_sparse
      sparse_to_dat
      recovery_patch
      create_zip_structure
      final_act
      ;;
      "5")
      make_rw
      get_image_size
      img2simg extracted/vendor.img $OUT""vendor.img 4096
      img_to_sparse
      sparse_to_dat
      recovery_patch
      create_zip_structure
      final_act
      ;;
      "6")
      make_rw
      cp extracted/boot.img $OUTFW""boot/boot.img
      vendor_patch
      get_image_size
      img_to_sparse
      sparse_to_dat
      create_zip_structure
      final_act
      ;;
      "7")
      make_rw
      get_image_size
      img2simg extracted/vendor.img $OUT""vendor.img 4096
      img_to_sparse
      sparse_to_dat
      magisk_patch
      create_zip_structure
      final_act
      ;;
      "8")
      make_rw
      get_image_size
      cp extracted/boot.img $OUTFW""boot/boot.img
      img2simg extracted/vendor.img $OUT""vendor.img 4096
      img_to_sparse
      sparse_to_dat
      create_zip_structure
      final_act
      ;;
     esac
}

source_check(){
    while [ -z "$file" ];
    do
        if [ -n "$(ls extracted/*.img &> /dev/null)" ]; then
            return
        else
            filepicker
        fi
    done
}

rom_dialog(){
    ROMTYPE=$(dialog --stdout --title 'Select ROM' --menu 'Select the rom type you want to convert:' 0 0 0 \
    1 'Two-Files Repack' \
    2 'One-File Repack')

    case "$ROMTYPE" in
    "1")
    OUT="./output/MIUI/rom/"
    OUTFW="./output/MIUI/fw/"
    mkdir -p $OUT $OUTFW
    comp_level=3
    ;;
    "2")
    OUT="./output/AOSP/"
    OUTFW="./output/AOSP/"
    mkdir -p $OUT
    compression_level
    ;;
    esac
    rom_updater_path="$OUT""META-INF/com/google/android"
    fw_updater_path="$OUTFW""META-INF/com/google/android"
    mkdir -p $OUTFW""boot $rom_updater_path
    mkdir -p $fw_updater_path $OUTFW""firmware-update $OUTFW""boot

}

magisk_choose_dialog(){
    magisk=$(dialog --stdout --title 'Select Magisk' --menu 'Make your pick::' 0 0 0 \
    1 'Use the current Magisk' \
    2 'Custom Magisk')

    case "$magisk" in
      "1")
      unset magisk
      return
      ;;
    esac

    magisk=$(dialog --stdout --title "USE SPACE TO SELECT MAGISK.ZIP" --fselect /sdcard/ -1 -1)
    unzip -l $magisk | grep -q libmagiskboot.so &> /dev/null
    if [ "$?" == "0" ]; then
        rm -rf .magisk && mkdir .magisk
        unzip -p $magisk lib/arm64-v8a/libmagiskboot.so > .magisk/magiskboot
        unzip -p $magisk lib/arm64-v8a/libbusybox.so > .magisk/busybox
        unzip -p $magisk lib/arm64-v8a/libmagisk64.so > .magisk/magisk64
        unzip -p $magisk lib/arm64-v8a/libmagiskinit.so > .magisk/magiskinit
        unzip -p $magisk assets/boot_patch.sh > .magisk/boot_patch.sh
        unzip -p $magisk assets/util_functions.sh > .magisk/util_functions.sh
        mkdir .magisk/chromeos
        unzip -j -qq $magisk assets/chromeos/* -d .magisk/chromeos/
        chmod +x *
    else
        echo -e "\e[1;31mYou made an invalid choice.\e[0m"
        sleep 3
        magisk_choose_dialog
    fi
}

select_mod(){ 
    mod=$(dialog --stdout --title 'Select MOD' --menu 'Select the number of the MOD:' 0 0 0 \
    1 'Magisk + TWRP + DFE' \
    2 'Magisk + DFE' \
    3 "Magisk + TWRP" \
    4 "TWRP + DFE" \
    5 "TWRP Only" \
    6 "DFE Only" \
    7 "Magisk Only" \
    8 "Just Repack")
    
    case "$mod" in
      "1")
      magisk_choose_dialog
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_Magisk+TWRP+DFE_repack"
      ;;
      "2")
      magisk_choose_dialog
      nameext="_Magisk+DFE_repack"
      ;;
      "3")
      magisk_choose_dialog
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_Magisk+TWRP_repack"
      ;;
      "4")
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_TWRP+DFE_repack"
      ;;
      "5")
      while [ -z "$twrp" ]; do twrp="$(sh recovery_manager.sh)"; done
      nameext="_TWRP_only_repack"
      ;;
      "6")
      nameext="_DFE_only_repack"
      ;;
      "7")
      magisk_choose_dialog
      nameext="_Magisk_only_repack"
      ;;
      "8")
      nameext="_only_repack"
      ;;
    esac
}

magisk_recovery_patch(){
    recovery_patch
    echo -e "\e[32m Patching kernel with Magisk...\e[0m"
    [ -z $magisk ] && magiskpath="/data/adb/magisk/" || magiskpath=".magisk"
    mv -f $OUTFW""boot/boot.img $magiskpath/
    sh $magiskpath/boot_patch.sh boot.img &> /dev/null
    rm $magiskpath/boot.img
    mv $magiskpath/new-boot.img $OUTFW""boot/boot.img
    rm -rf .magisk
    echo -e "\e[1;32m Magisk patch is done.\e[0m"
}

magisk_patch(){
    echo -e "\e[32m Patching kernel with Magisk...\e[0m"
    [ -z $magisk ] && magiskpath="/data/adb/magisk/" || magiskpath=".magisk"
    cp extracted/boot.img $magiskpath/
    sh $magiskpath/boot_patch.sh boot.img &> /dev/null
    rm $magiskpath/boot.img
    mv $magiskpath/new-boot.img $OUTFW""boot/boot.img
    rm -rf .magisk
    echo -e "\e[1;32m Magisk patch is done.\e[0m"
}

recovery_patch(){
    chmod +x aik/*
    echo -e "\e[32m Patching kernel with TWRP...\e[0m"
    cp extracted/boot.img aik/
    aik/unpackimg.sh boot.img &> /dev/null
    rm -rf aik/ramdisk/*
    tar xf twrp/"$twrp" -C aik/
    aik/repackimg.sh --origsize &> /dev/null
    mv aik/image-new.img $OUTFW""boot/boot.img
    aik/cleanup.sh &> /dev/null
    echo -e "\e[1;32m Recovery patch is done.\e[0m"
}

get_image_size(){
    VENDOR=$(expr $(stat -c%s extracted/vendor.img | cut -f1) + 300000000)
    SYSTEM="$(stat -c%s extracted/system.img | cut -f1)"
    SYSTEMEXT="$(stat -c%s extracted/system_ext.img | cut -f1)"
    PRODUCT="$(stat -c%s extracted/product.img | cut -f1)"
    if [ ! -z "$(ls extracted | grep odm.img)" ]; then
        ODM="$(stat -c%s extracted/odm.img | cut -f1)"
    fi
}

vendor_patch(){
    tune2fs -f -O ^read-only extracted/vendor.img &> /dev/null
    echo -e "\e[1m\e[37m Mounting vendor.img... \e[0m"
    sh rw.sh extracted/vendor.img &> /dev/null    
    mount extracted/vendor.img tmp/
    echo -e "\e[1;32m Vendor image has temporarily been mounted.\e[0m"
    sh dfe.sh tmp/
    umount tmp
    if [ $rw == 0 ]; then
        tune2fs -f -O read-only extracted/vendor.img &> /dev/null
    fi
    img2simg extracted/vendor.img $OUT""vendor.img 4096
}

make_rw(){
    [ "$rw" == "0" ] && return
    echo -e "\e[1m\e[37mGiving read and write permissions...\e[0m"
    for img in extracted/*img; do
        case "$(basename $img /)" in
         (system.img|system_ext.img|product.img|odm.img)
          sh rw.sh $img &> /dev/null
          e2fsck -fy $img &> /dev/null
         esac
    done
}

img_to_sparse(){
    for file in $(ls -1 extracted/*.img | xargs -n1 basename)
    do
        if ! case "$file" in (system.img|product.img|system_ext.img|odm.img) false; esac; then
            echo -e "\e[32m--------------------------------------------------------\e[0m"
            echo -e "\e[32mConverting ${file}...\e[0m"
            echo -e "\e[32m--------------------------------------------------------\e[0m"
            img2simg extracted/$file $OUT""$file 4096
            echo -e "\e[1;32m${file} successfully converted.\e[0m"
            continue
        fi
        if ! case "$file" in (vendor_boot.img|dtbo.img) false; esac; then
            if [ "$ROMTYPE" == "1" ]; then 
                cp extracted/$file $OUTFW"boot/"
                continue
            else
                cp extracted/$file $OUT"boot/"
                continue
            fi
        fi
        if [[ $file == "vendor.img" || $file == "boot.img" ]]; then
            continue
        fi
        cp extracted/$file $OUTFW"firmware-update/"
    done
    echo
    echo
}

sparse_to_dat(){
    for sparse in $(ls -1 $OUT/*.img | xargs -n1 basename)
    do
        echo -e "\e[32m--------------------------------------------------------\e[0m"
        echo -e "\e[32mConverting $sparse into ${sparse%.*}.new.dat...\e[0m"
        echo -e "\e[32m--------------------------------------------------------\e[0m"
        img2sdat $OUT""$sparse -v4 -o $OUT -p ${sparse%.*}
        rm $OUT""$sparse
        echo
        echo -e "\e[1;32m$sparse has been successfully converted into ${sparse%.*}.new.dat\e[0m"
        echo
    done

    if [[ $comp_level -gt 0 || "$ROMTYPE" == 1 ]]; then
        for dat in $(ls -1 $OUT/*.new.dat | xargs -n1 basename)
        do
            echo -e "\e[32m--------------------------------------------------------\e[0m"
            echo -e "\e[32mConverting $dat into ${dat%.*}.br...\e[0m"
            echo -e "\e[32m--------------------------------------------------------\e[0m"
            echo
            brotli -$comp_level -j $OUT""$dat
            echo -e "\e[1;32m$dat converted into ${dat%.*}.dat.br\e[0m"
            echo
        done
    fi
}

create_zip_structure(){
    [ -z "$rename" ] && rename="UnnamedRom"
    echo -e "ui_print(\"*****************************\");\n" \
                 "ui_print(\" - $rename by AutoRepack\");\n" \
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
        echo -e "\nassert(update_dynamic_partitions(package_extract_file(\"dynamic_partitions_op_list\")));\n" >> $fw_updater_path/updater-script
        echo -e "ui_print(\"Flashing vendor_a partition...\");" >> $fw_updater_path/updater-script
        echo -e "block_image_update(map_partition(\"vendor_a\"), package_extract_file(\"vendor.transfer.list\"), \"vendor.new.dat.br\", \"vendor.patch.dat\") ||" \
        "abort(\"E2001: Failed to flash vendor_a partition.\");\n\n" >> $fw_updater_path/updater-script
        echo -e "show_progress(0.100000, 10);\n" \
                 "run_program(\"/system/bin/bootctl\", \"set-active-boot-slot\", \"0\");\n" \
                 "set_progress(1.000000);" | sed 's/^ *//g' >> $fw_updater_path/updater-script
        echo -e "ui_print(\"*****************************\");\n" \
                 "ui_print(\" - $rename by AutoRepack\");\n" \
                 "ui_print(\"*****************************\");\n\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_root\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/product\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_ext\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/odm\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/vendor\");\n" \
                 "ui_print(\"Flashing partition images...\");\n" | sed 's/^ *//g' >> $rom_updater_path/updater-script
        cp bin/aarch64-linux-gnu/update-binary $fw_updater_path
     ;;
    esac
    cp bin/aarch64-linux-gnu/update-binary $rom_updater_path
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
      echo -e "resize vendor_a $VENDOR" >>$OUTFW"dynamic_partitions_op_list"
     ;;
     2)
      echo -e "resize vendor_a $VENDOR" >>$OUT"dynamic_partitions_op_list"
     ;;
    esac
    if [ ! -z "$(ls extracted | grep odm.img)" ]; then
      echo -e "resize odm_a $ODM" >>$OUT"dynamic_partitions_op_list"
    fi
}

final_act(){
    echo
    echo -e "\e[32m -------------------------------------------------------\e[0m"
    echo -e "\e[32m            Creating flashable repack rom.\e[0m"
    echo -e "\e[32m -------------------------------------------------------\e[0m"
    echo
    [ ! -z "$repackrename" ] && repackname=$repackrename
    if [ $ROMTYPE == "1" ]; then
        mv output/MIUI/rom/vendor* $OUTFW
        echo
        echo -e "\e[1m\e[37mPacking MIUI firmware files...\e[0m"
        echo
        cd output/MIUI/fw
        zip -r $repackname$nameext-Step2.zip META-INF *
        echo
        echo -e "\e[1m\e[37mPacking MIUI rom files...\e[0m"
        echo
        cd ../rom
        zip -r $repackname$nameext-Step1.zip META-INF *
        mv $(find ../ -name '*.zip') /sdcard/Repacks/
    else
        echo -e "\e[1m\e[37mPacking rom files...\e[0m"
        echo
        cd $OUT
        zip -r $repackname$nameext.zip META-INF *
        mv $(find . -name '*.zip') /sdcard/Repacks/
    fi
    echo -e "\e[1;32mYour repacked rom is ready to flash. You can find it in /sdcard/Repacks/ \e[0m"
    sh cleanup.sh &> /dev/null
    exit
}

rm -rf tmp/* output
integrity_check
file_renamer
source_check
