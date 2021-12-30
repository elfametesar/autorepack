#!$PREFIX/bin/bash

export PATH=$PWD/bin:$PATH
export LC_ALL=C
export TERM=linux
export TERMINFO=$PREFIX/share/terminfo/
mkdir -p /sdcard/Repacks
HOME=$PWD

trap "jobs -p | xargs -n 1 kill -9 &> /dev/null" EXIT

calc(){ awk 'BEGIN{ print int('$1') }'; }

integrity_check(){
    [ -z "`ls extracted | grep '.img'`" ] && sh cleanup.sh && return
    for check in `ls extracted | grep .img`;
    do
        case $check in (system.img|product.img|system_ext.img|boot.img|vendor_boot.img|dtbo.img)
           ((headcount++))
        esac
    done
    if ((headcount != 6)); then
        dialog --title "Integrity Check" --msgbox "There are some useless leftover .img files in the workspace. They will be cleaned up." 6 50
        sh cleanup.sh &> /dev/null
    else
        dialog --yesno "You already have some extracted img files in workspace. Do you want to continue with them?" 6 50
        (($? == 0)) && ui_menu && rom_dialog && select_mod && start_repack || sh cleanup.sh || return
    fi
}

ui_menu(){
    [ ! -f ".conf" ] && menu
    [ ! -f ".conf" ] && exit
    read -d "\n" file name ROMTYPE fw rw comp_level mm magisk addons <<< `sed 's/[][]//g' .conf`
    ((mm == 0)) && unset magisk
}

successbar(){
    extractTo=$1
    extract_type=$2
    fullsize=$3
    (
    while ((${current:=0} != 100));
    do
        curfile=`ls -tc $extractTo | head -n 1`
        chunk=`du -sb $extractTo | cut -f1`
        current=`calc "($chunk/$fullsize)*100"`
        echo $current
        echo "XXX"
        echo "‎"
        echo "Files are extracting: $curfile"
        echo "XXX"
        sleep 1
     done
     ) |
     dialog  --title "$extract_type" --gauge "" 7 70 0
}

payload_extract(){
    paydump -c 8 -o extracted/ "$file" &> /dev/null &
    successbar extracted "Payload Image Extraction" `paydump -l $file | tail -1`
    if [ ! "$fw" == "None" ]; then
        if ( unzip -l "$fw" | grep -q .img ); then
            7za e -otmp/ "$fw" *.img -r -y &> /dev/null &
            successbar "tmp/" "Firmware Extraction" `7za l "$fw" *.img -r | awk 'END{ print $3 }'`
        fi
        mv tmp/* extracted/
    fi
}

fastboot_extract(){
    if [[ "$file" == *.tgz ]]; then
        printf "\e[37m%s\e[0m\n" "Retrieving information from archive..."
        7za e -so "$file" -mmt8 | 7za e -si -ttar *.img -r -mmt8 -otmp/ &> /dev/null &
        successbar tmp "Fastboot Image Extraction" `7za e -so "$file" -mmt8 | 7za l -si -ttar *.img -r -mmt8 | awk 'END{ print $4 }'`
    else
        7za e "$file" -otmp/ *.img -y -r -mmt8 &> /dev/null &
        successbar tmp "Fastboot Image Extraction" `7za l "$file" *.img -r | grep "files" | awk '{ print $3 }'`
    fi
    printf "%s\n"
    if ( file tmp/super.img | grep -q sparse ); then
        printf "\e[37m%s\e[0m\n" "Converting super.img to raw..."
        simg2img tmp/super.img extracted/super.img
        rm tmp/super.img
    fi
    [ ! -z "`ls tmp | grep .img`" ] && mv tmp/*.img extracted/
    printf "\e[37m%s\e[0m\n" "Unpacking super..."
    lpunpack --slot=0 extracted/super.img extracted/
    rm extracted/super.img
    for file in extracted/*_a.img ; do
        mv $file extracted/${file%%_a.img}
    done
    rm -rf tmp/* extracted/*_b.img extracted/rescue.img extracted/userdata.img extracted/dummy.img extracted/persist.img extracted/metadata.img extracted/metadata.img
    if [ ! "$fw" == "None" ]; then
        if ( unzip -l "$fw" | grep -q .img ); then
            7za e -otmp/ "$fw" *.img -r -y &> /dev/null &
            successbar tmp "Firmware Extraction" `7za l "$fw" *.img -r | awk 'END{ print $3 }'`
        fi
        mv tmp/* extracted/
    fi
}


filepicker(){
    case "$file" in
     *.tgz)
        rom_dialog
        select_mod
        fastboot_extract
     ;;
     *.zip)
        if ( unzip -l "$file" | grep -q payload.bin ); then
            rom_dialog
            select_mod
            7za e -otmp/ "$file" payload.bin -y -mmt8 &> /dev/null &
            successbar tmp "Payload.bin Extraction" `7za l "$file" *.bin | awk 'END{ print $4 }'`
            file=tmp/payload.bin
            payload_extract
            rm -rf tmp/*
        else
            if ( 7za l "$file" super.img -r | grep -q "$super.img$" ); then
                rom_dialog
                select_mod
                fastboot_extract
            else
                printf "\e[1;31m%s\e[0m\n" "You did not choose a valid file" 1>&2
                exit
            fi
        fi
     ;;
     *.7z)
        if ( 7za l "$file" super.img -r | grep -q $super.img$ ); then
            rom_dialog
            select_mod
            fastboot_extract
        else
            printf "\e[1;31m%s\e[0m\n" "You did not choose a valid file" 1>&2
            exit
        fi
     ;;
     *.bin)
        rom_dialog
        select_mod
        payload_extract
     ;;
     ''|*)
        printf "\e[1;31m%s\e[0m\n" "You did not choose a valid file" 1>&2
        exit
     ;;
    esac
    start_repack
}


start_repack(){
    case $mod in
      "1")
        make_rw
        get_image_size
        img_to_sparse
        magisk_patch
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
        ln -n extracted/boot.img ${OUTFW}boot/boot.img
        get_image_size
        img_to_sparse
        get_image_size
        final_act
      ;;
      "12")
        make_rw
        get_image_size
        img_to_sparse
        recovery_patch
        magisk_patch
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
      "23")
        make_rw
        vendor_patch
        get_image_size
        img_to_sparse
        recovery_patch
        get_image_size
        final_act
      ;;
      "123")
        make_rw
        vendor_patch
        get_image_size
        img_to_sparse
        recovery_patch
        magisk_patch
        get_image_size
        final_act
      ;;
      "")
        make_rw
        get_image_size
        ln -n extracted/boot.img ${OUTFW}boot/boot.img
        img_to_sparse
        get_image_size
        final_act
      ;;
     esac
}

rom_dialog(){
    case $ROMTYPE in
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
    rom_updater_path="${OUT}META-INF/com/google/android"
    fw_updater_path="${OUTFW}META-INF/com/google/android"
    mkdir -p ${OUTFW}boot $rom_updater_path
    mkdir -p $fw_updater_path ${OUTFW}firmware-update ${OUTFW}boot

}

magisk_choose_dialog(){
    [ -z "$magisk" ] && return
    unzip -l "$magisk" | grep -q lib/arm64-v8a/libmagiskboot.so
    (( $? == 0 )) && arch="arm64-v8a" || arch="armeabi-v7a"
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
    ( grep -q 'Magisk' <<< $addons ) && mod+="1"
    ( grep -q 'Recovery' <<< $addons ) && mod+="2"
    ( grep -q 'DFE' <<< $addons ) && mod+="3"
    case $mod in
      "123")
        magisk_choose_dialog
        while [ -z "$twrp" ]; do twrp=`sh recovery_manager.sh`; done
        nameext="_Magisk+TWRP+DFE_repack"
      ;;
      "13")
        magisk_choose_dialog
        nameext="_Magisk+DFE_repack"
      ;;
      "12")
        magisk_choose_dialog
        while [ -z "$twrp" ]; do twrp=`sh recovery_manager.sh`; done
        nameext="_Magisk+TWRP_repack"
      ;;
      "23")
        while [ -z "$twrp" ]; do twrp=`sh recovery_manager.sh`; done
        nameext="_TWRP+DFE_repack"
      ;;
      "2")
        while [ -z "$twrp" ]; do twrp=`sh recovery_manager.sh`; done
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

magisk_patch(){
    printf "\e[32m%s\e[0m\n" " Patching kernel with Magisk..."
    [ ! -d ".magisk" ] && cp -rf /data/adb/magisk/ .magisk
    [[ $mod =~ 2 ]] && mv ${OUTFW}boot/boot.img .magisk || ln -n extracted/boot.img .magisk/
    sh .magisk/boot_patch.sh boot.img &> /dev/null
    rm .magisk/boot.img
    mv .magisk/new-boot.img ${OUTFW}boot/boot.img
    rm -rf .magisk
    printf "\e[1;32m%s\e[0m\n" " Magisk patch is done"
}

recovery_patch(){
    printf "\e[32m%s\e[0m\n" " Patching kernel with TWRP..."
    [ ! -d ".magisk" ] && cp -rf /data/adb/magisk/ .magisk
    ln -n extracted/boot.img .magisk/
    cd .magisk
    ./magiskboot unpack boot.img &> /dev/null
    tar xf ../twrp/"$twrp" -C ./
    ./magiskboot cpio ramdisk.cpio sha1 &> /dev/null
    ./magiskboot repack boot.img &> /dev/null
    cd ..
    mv .magisk/new-boot.img ${OUTFW}boot/boot.img
    .magisk/magiskboot cleanup &> /dev/null
    printf "\e[1;32m%s\e[0m\n" " Recovery patch is done"
}

get_image_size(){
    VENDOR=`stat -c%s extracted/vendor.img`
    SYSTEM=`stat -c%s extracted/system.img`
    SYSTEMEXT=`stat -c%s extracted/system_ext.img`
    PRODUCT=`stat -c%s extracted/product.img`
    [ ! -f extracted/odm.img ] && ODM=`stat -c%s extracted/odm.img`
    total=`calc $VENDOR+$SYSTEM+$SYSTEMEXT+$PRODUCT+${ODM:=0}`
}

vendor_patch(){
    tune2fs -f -O ^read-only extracted/vendor.img &> /dev/null
    process_rw extracted/vendor.img &> /dev/null
    printf "\e[1m\e[1;37m%s\e[0m\n" " Mounting vendor.img..."
    umount tmp &> /dev/null
    while (( ${count:=0} < 6 )); do
        let "count++"
        mount extracted/vendor.img tmp/ &> /dev/null
        ( mountpoint -q tmp/ ) && break
    done
    if ( mountpoint -q tmp/ ); then
        printf "\e[1;32m%s\e[0m\n" " Vendor image has temporarily been mounted"
        sh dfe.sh tmp/ &> /dev/null
        sh dfe.sh tmp/ 
        sed -i 's/encrypted/unsupported/' tmp/etc/init/hw/init.gourami.rc &> /dev/null
        umount tmp
    else
        printf "\e[1;31m%s\e[0m\n" " Vendor image could not be mounted. Continuing without DFE patch" 1>&2
    fi
    (( rw == 0 )) && tune2fs -f -O read-only extracted/vendor.img &> /dev/null
}

process_rw(){
    imgsize=`stat -c%s $1`
    new_size=`calc $imgsize*1.25/512`
    resize2fs -f $1 ${new_size}s
    e2fsck -y -E unshare_blocks $1
    resize2fs -f -M $1
    resize2fs -f -M $1
    
    imgsize=`stat -c%s $1`
    new_size=`calc "($imgsize+20*1024*1024)/512"`
    resize2fs -f $1 ${new_size}s
}

make_rw(){
    (( rw == 0 )) && return
    printf "\e[1;37m%s\e[0m\n" "Giving read and write permissions..."
    for img in `ls extracted/ | grep .img`; do
        case $img in
         (system.img|system_ext.img|vendor.img|product.img|odm.img)
             ( tune2fs -l extracted/$img | grep -q 'shared_blocks' ) && continue
             process_rw extracted/$img &> /dev/null
         esac
    done
}

multi_process(){
    img2simg extracted/$file ${OUT}$file 4096
    img2sdat ${OUT}$file -v4 -o $OUT -p ${file%.*} 
    rm ${OUT}$file && \
    (( $comp_level > 0 )) && \
        brotli -$comp_level -j ${OUT}${file%.*}.new.dat
}

img_to_sparse(){
    printf "\n\e[1;32m%s\e[0m\n" " Converting images in background"
    empty_space=`calc 8988393472-$total`
    for file in `ls -1 extracted | grep .img`
    do
        case $file in 
          system.img|product.img|system_ext.img|odm.img|vendor.img)
              if (( SYSTEM < 4194304000 )); then
                  case $file in 
                    odm.img)
                        multi_process &> /dev/null &
                        continue
                    ;;
                    system.img)
                        new_size=`calc $SYSTEM+$empty_space/2`
                    ;;
                    *)
                        new_size=`calc $(stat -c%s extracted/$file)+$empty_space/2/3`
                    ;; esac
                  fallocate -l $new_size extracted/$file
                  resize2fs -f extracted/$file &> /dev/null
              fi
              multi_process &> /dev/null &
              continue
            ;;
          vendor_boot.img|dtbo.img)
              (( ROMTYPE == 1 )) && ln extracted/$file $OUTFW"boot/" && continue || ln extracted/$file $OUT"boot/" || continue
          ;;
          boot.img)
              continue
          ;;
          *)
              ln -n extracted/$file $OUTFW"firmware-update/"
        esac
    done
    printf "%s\n"
}

create_zip_structure(){
    [ "$name" == "None" ] && name="UnnamedRom"
    echo -e "ui_print(\"*****************************\");\n" \
                 "ui_print(\" - $name by AutoRepack\");\n" \
                 "ui_print(\"*****************************\");\n\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_root\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/product\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/system_ext\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/odm\");\n" \
                 "run_program(\"/sbin/busybox\", \"umount\", \"/vendor\");\n" \
                 "ui_print(\"Flashing partition images...\");\n" | sed 's/^ *//g' >> $fw_updater_path/updater-script
    for fw in `ls ${OUTFW}firmware-update/ ${OUTFW}boot/ | grep .img`; do
        case $fw in boot.img|vendor_boot.img|dtbo.img)
            root="boot"
        ;;
        *)
            root="firmware-update"
        ;; esac
        echo -e "package_extract_file(\"$root/$fw\", \"/dev/block/bootdevice/by-name/${fw%%.img}_a\");" >> $fw_updater_path/updater-script
        echo -e "package_extract_file(\"$root/$fw\", \"/dev/block/bootdevice/by-name/${fw%%.img}_b\");\n" >> $fw_updater_path/updater-script
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
    for partition in `ls $OUT | grep .new.dat`; do
        echo -e "ui_print(\"Flashing ${partition%%.*}_a partition...\");\n" \
        "show_progress(0.100000, 0);\n" \
        "block_image_update(map_partition(\"${partition%%.*}_a\"), package_extract_file(\"${partition%%.*}.transfer.list\"), \"$partition\", \"${partition%%.*}.patch.dat\") ||" \
        "abort(\"E2001: Failed to flash ${partition%%.*}_a partition.\");\n" | sed 's/^ *//g' >> $rom_updater_path/updater-script
    done
    echo -e "\nshow_progress(0.100000, 10);\n" \
             "run_program(\"/system/bin/bootctl\", \"set-active-boot-slot\", \"0\");\n" \
             "set_progress(1.000000);" | sed 's/^ *//g' >> $rom_updater_path/updater-script
    printf "%s\n"
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
    printf "\n\e[32m%s\e[0m\n" " Waiting for image processes to be done"
    wait
    create_zip_structure
    printf "\n\e[32m%s\e[0m\n" " -------------------------------------------------------"
    printf "\e[32m%s\e[0m\n" "            Creating flashable repack rom"
    printf "\e[32m%s\e[0m\n\n" " -------------------------------------------------------"
    if (( ROMTYPE == 1 )); then
        printf "\n\e[1m\e[37m%s\e[0m\n\n" "Packing firmware files..."
        cd output/MIUI/fw
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext"-Step2.zip * -bso0
        printf "\n\e[1m\e[37m%s\e[0m\n\n" "Packing rom files..."
        cd ../rom
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext"-Step1.zip * -bso0
    else
        printf "\e[1m\e[37m%s\e[0m\n\n" "Packing rom files..."
        cd $OUT
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext".zip * -bso0
    fi
    cd $HOME
    sh cleanup.sh &> /dev/null
    printf "\e[1;32m%s\e[0m\n\n" "Your repacked rom is ready to flash. You can find it in /sdcard/Repacks/"
    exit
}

rm -rf tmp/* output .magisk
integrity_check
ui_menu
filepicker
