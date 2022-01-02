#!/data/local/autorepack/bin/bash

export PATH=$PWD/bin:$PATH
export LC_ALL=C
export TERM=linux
export TERMINFO=$PREFIX/share/terminfo/
mkdir -p /sdcard/Repacks
HOME=$PWD

trap "jobs -p | xargs -n 1 kill -9 &> /dev/null; exit" EXIT INT

calc(){ awk 'BEGIN{ print int('$1') }'; }

cleanup(){
    case $1 in
      --deep)
        rm -rf .magisk extracted/* output tmp/* .conf
      ;;
      --soft)
        rm -rf .magisk tmp/* output
      ;; esac
}

integrity_check(){
    [ -z "`ls extracted | grep '.img'`" ] && cleanup --deep && main
    for check in extracted/*.img; {
        case ${check##*/} in (system.img|product.img|system_ext.img|boot.img|vendor_boot.img|dtbo.img)
           ((headcount++))
        esac
    }
    ((headcount != 6)) && {
        dialog --stdout --title "Integrity Check" --msgbox \
            "There are some useless leftover .img files in the workspace. They will be cleaned up." 6 50
        cleanup --deep
        main
    } ||
    {
        dialog --stdout --yesno \
            "You already have some extracted img files in workspace. Do you want to continue with them?" 6 50
        (($? == 0)) && cleanup --soft && main dirty || cleanup --deep && main
    }
}

workspace_setup(){
    [ -f ".conf" ] || menu && [ -f ".conf" ] || exit
    IFS="|" read file name mode fw rw comp_level mm magisk addons <<< `awk -F ': ' 'ORS="|" {print $2}' .conf`
    name=${name%.*}
    ((mm == 0)) && unset magisk
    case $mode in
      "0")
        OUT="./output/ModeOne/"
        OUTFW="./output/ModeOne/"
        mkdir -p $OUT
    ;;
     "1")
        OUT="./output/ModeTwo/rom/"
        OUTFW="./output/ModeTwo/fw/"
        mkdir -p $OUT $OUTFW
    ;;
    esac
    rom_updater_path="${OUT}META-INF/com/google/android"
    fw_updater_path="${OUTFW}META-INF/com/google/android"
    mkdir -p ${OUTFW}boot $rom_updater_path
    mkdir -p $fw_updater_path ${OUTFW}firmware-update ${OUTFW}boot
    ( grep -q 'Magisk' <<< $addons ) && custom_magisk && nameext+="+Magisk"
    ( grep -q 'Recovery' <<< $addons ) && nameext+="+Recovery" \
        && while [ -z "$twrp" ]; do twrp=`sh recovery_manager.sh`; done
    ( grep -q 'DFE' <<< $addons ) && nameext+="+DFE"
    nameext+="_repack"
}

successbar(){
    (
    while ((${current:=0} != 100)); do
        curfile=`ls -tc $1 | head -n 1`
        chunk=`du -sb $1 | cut -f1`
        current=`calc "($chunk/$3)*100"`
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
    firmware_extract
}

firmware_extract(){
    rm -rf tmp/*
    [ "$fw" == "None" ] || {
        ( 7za l "$fw" "*.img" -r | grep -q .img ) && {
            7za e -otmp/ "$fw" "*.img" -r -y &> /dev/null &
            successbar tmp/ "Firmware Extraction" `7za l "$fw" "*.img" -r | awk 'END{ print $3 }'`
        }
        mv tmp/* extracted/
    }
}

fastboot_extract(){
    echo
    ( file tmp/super.img | grep -q sparse ) && {
        printf "\e[37m%s\e[0m\n" "Converting super.img to raw..."
        simg2img tmp/super.img extracted/super.img
        rm tmp/super.img
    }
    [ -z "`ls tmp | grep .img`" ] || mv tmp/*.img extracted/
    printf "\e[37m%s\e[0m\n" "Unpacking super..."
    lpunpack --slot=0 extracted/super.img extracted/
    rm extracted/super.img
    for file in extracted/*_a.img; { mv $file ${file%%_a.img}.img; }
    rm -rf extracted/*_b.img extracted/rescue.img extracted/userdata.img extracted/dummy.img\
           extracted/persist.img extracted/metadata.img extracted/metadata.img
    firmware_extract
}

file_extractor(){
    case $file in
     *.tgz)
        printf "\e[37m%s\e[0m\n" "Retrieving information from archive..."
        rom_name=${file##*/}
        7za e "$file" -y -mmt8 -bso0 -bsp0 -o. && size=`7za l "${rom_name%.tgz}.tar" -ttar "*.img" -r -mmt8 | awk 'END{ print $4 }'`
        7za e "${rom_name%.tgz}.tar" -y -bso0 -bsp0 -sdel -ttar "*.img" -r -mmt8 -otmp/ &
        successbar tmp "Fastboot Image Extraction" $size
        fastboot_extract
     ;;
     *.7z|*.zip|*.bin)
        [[ "$file" == *.bin ]] && payload_extract && return
        content=`7za l "$file" payload.bin super.img -r`
        ( grep -q payload.bin <<< $content ) && {
            7za e -otmp/ "$file" payload.bin -y -mmt8 &> /dev/null &
            successbar tmp "Payload.bin Extraction" \
                              `7za l "$file" payload.bin | awk 'END{ print $4 }'`
            file=tmp/payload.bin
            payload_extract
            rm -rf tmp/*
        }
        ( grep -q "$super.img$" <<< $content ) && {
            7za e "$file" -otmp/ "*.img" -y -r -mmt8 &> /dev/null &
            successbar tmp "Fastboot Image Extraction" \
                    `7za l "$file" "*.img" -r | grep "files" | awk '{ print $3 }'`
            fastboot_extract
        }
     ;;
     ''|*)
        printf "\e[1;31m%s\e[0m\n" "You did not choose a valid file" 1>&2
        exit
     ;;
    esac
}

custom_magisk(){
    [ -z "$magisk" ] && return
    7za l "$magisk" lib/arm64-v8a/libmagiskboot.so lib/armeabi/libmagiskboot.so | grep -q libmagiskboot.so
    (( $? == 0 )) && arch="arm64-v8a" || arch="armeabi-v7a"
    rm -rf .magisk && mkdir -p .magisk/chromeos
    7za e -y -bso0 "$magisk" lib/$arch/libmagiskboot.so \
                                lib/$arch/libbusybox.so \
                                lib/$arch/libmagisk64.so \
                                lib/$arch/libmagiskinit.so \
                                assets/boot_patch.sh \
                                assets/util_functions.sh -o.magisk/
    for lib in .magisk/lib*; {
        lib=${lib%.so}
        mv ${lib}.so $lib
        mv $lib .magisk/${lib#*lib}
    }
    chmod -R +x .magisk
}

patch_magisk(){
    [[ "$addons" =~ Magisk ]] || return
    printf "\e[32m%s\e[0m\n" " Patching kernel with Magisk..."
    [ -d ".magisk" ] || cp -rf /data/adb/magisk/ .magisk
    [[ $addons =~ Recovery ]] && mv ${OUTFW}boot/boot.img .magisk || ln -n extracted/boot.img .magisk/
    sh .magisk/boot_patch.sh boot.img &> /dev/null
    rm .magisk/boot.img
    mv .magisk/new-boot.img ${OUTFW}boot/boot.img
    rm -rf .magisk
    printf "\e[1m\e[1;32m%s\e[0m\n" " Magisk patch is done"
}

patch_recovery(){
    [[ "$addons" =~ Recovery ]] || return
    printf "\e[32m%s\e[0m\n" " Patching kernel with TWRP..."
    [ -d ".magisk" ] || cp -rf /data/adb/magisk/ .magisk
    ln -n extracted/boot.img .magisk/
    cd .magisk
    ./magiskboot unpack boot.img &> /dev/null
    tar xf ../twrp/"$twrp" -C ./
    ./magiskboot cpio ramdisk.cpio sha1 &> /dev/null
    ./magiskboot repack boot.img &> /dev/null
    cd ..
    mv .magisk/new-boot.img ${OUTFW}boot/boot.img
    .magisk/magiskboot cleanup &> /dev/null
    printf "\e[1m\e[1;32m%s\e[0m\n" " Recovery patch is done"
}

patch_vendor(){
    [[ "$addons" =~ DFE ]] || return
    tune2fs -f -O ^read-only extracted/vendor.img &> /dev/null
    (( rw == 0 )) && grant_rw extracted/vendor.img &> /dev/null
    printf "\e[1m\e[1;37m%s\e[0m\n" " Mounting vendor.img..."
    ( mountpoint -q tmp ) && umount tmp
    while (( ${count:=0} < 6 )); do
        (( count++ ))
        mount extracted/vendor.img tmp/ &> /dev/null
        ( mountpoint -q tmp/ ) && break
    done
    ( mountpoint -q tmp/ ) && {
        printf "\e[1;32m%s\e[0m\n" " Vendor image has temporarily been mounted"
        sh dfe.sh tmp/ 
        sed -i 's/encrypted/unsupported/' tmp/etc/init/hw/init.gourami.rc &> /dev/null
        umount tmp
    } ||
    {
        printf "\e[1;31m%s\e[0m\n" " Vendor image could not be mounted. Continuing without DFE patch" 1>&2
    }
    (( rw == 0 )) && tune2fs -f -O read-only extracted/vendor.img &> /dev/null
}

get_image_size(){
    VENDOR=`stat -c%s extracted/vendor.img`
    SYSTEM=`stat -c%s extracted/system.img`
    SYSTEMEXT=`stat -c%s extracted/system_ext.img`
    PRODUCT=`stat -c%s extracted/product.img`
    [ -f extracted/odm.img ] && ODM=`stat -c%s extracted/odm.img`
    total=`calc $VENDOR+$SYSTEM+$SYSTEMEXT+$PRODUCT+${ODM:=0}`
}

grant_rw(){
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

multi_process_sparse(){
    file=${file##*/}
    img2simg extracted/$file ${OUT}$file 4096
    img2sdat ${OUT}$file -v4 -o $OUT -p ${file%.*} 
    rm ${OUT}$file && \
    (( $comp_level > 0 )) && \
        brotli -$comp_level -j ${OUT}${file%.*}.new.dat
}

img_to_sparse(){
    printf "\n\e[1;32m%s\e[0m\n" " Converting images in background"
    printf "\e[1;37m%s\e[0m\n" " Giving read and write permissions..."
    empty_space=`calc 8988393472-$total`
    for file in extracted/*.img; {
        case ${file##*/} in system.img|product.img|system_ext.img|odm.img|vendor.img)
            (( rw == 1 )) && {
                ( tune2fs -l $file | grep -q 'shared_blocks' ) && grant_rw $file &> /dev/null
            } 
            [ ${file##*/} == "vendor.img" ] && patch_vendor
            (( SYSTEM > 4694304000 )) && { multi_process_sparse $file &> /dev/null & continue; }
            case ${file##*/} in odm.img)
                multi_process_sparse $file &> /dev/null &
                continue
            ;;
            system.img)
                new_size=`calc $SYSTEM+$empty_space/2`
            ;;
            *)
                new_size=`calc $(stat -c%s $file)+$empty_space/2/3`
            esac
            fallocate -l $new_size $file
            resize2fs -f $file &> /dev/null
            multi_process_sparse $file &> /dev/null &
        ;;
        vendor_boot.img|dtbo.img)
            (( mode == 1 )) && ln $file ${OUTFW}boot/ && continue || \
                                         ln $file ${OUT}boot/ || continue
        ;;
        boot.img)
            continue
        ;;
        *)
            ln -n $file ${OUTFW}firmware-update/
        esac
    }
    echo
}

create_zip_structure(){
    [ "$name" == "None" ] && name="UnnamedRom"
    header=`cat <<EOF | sed 's/^ *//g; s/^$/ /'
                  ui_print("*****************************");
                  ui_print(" - $name by AutoRepack"); 
                  ui_print("*****************************");

                  run_program("/sbin/busybox", "umount", "/system_root");
                  run_program("/sbin/busybox", "umount", "/product");
                  run_program("/sbin/busybox", "umount", "/system_ext");
                  run_program("/sbin/busybox", "umount", "/odm");
                  run_program("/sbin/busybox", "umount", "/vendor");
 
                  ui_print("Flashing partition images..."); 
EOF
`
    for partition in ${OUT}*.new.dat*; {
        partition=${partition##*/}
        partition_lines+=`cat <<EOF | sed 's/^ *//g; s/^$/ /'

        ui_print("Flashing ${partition%%.*}_a partition..."); 
        show_progress(0.100000, 0); 
        block_image_update(map_partition("${partition%%.*}_a"), package_extract_file("${partition%%.*}.transfer.list"), "$partition", "${partition%%.*}.patch.dat") || abort("E2001: Failed to flash ${partition%%.*}_a partition.");

EOF

`
    }
    for fw in ${OUTFW}firmware-update/* ${OUTFW}boot/*; {
        fw=${fw##*/}
        case $fw in boot.img|vendor_boot.img|dtbo.img)
            root="boot"
        ;;
        *)
            root="firmware-update"
        ;; esac
        fw_lines+=`cat <<EOF | sed 's/^ *//g; s/^$/ /'
 
                package_extract_file("$root/$fw", "/dev/block/bootdevice/by-name/${fw%%.img}_a");
                package_extract_file("$root/$fw", "/dev/block/bootdevice/by-name/${fw%%.img}_b");
 
EOF
`
    }
    case $mode in 
     1)
        fw_lines+=`sed -n '/. *Flashing vendor_a.*/{xNNN;p}' <<< $partition_lines`
        partition_lines=`sed -n '/. *Flashing vendor_a.*/{NNN;d}p' <<< $partition_lines`
        mv ${OUT}vendor* $OUTFW
        cat <<EOF | sed 's/^ *//g; s/^$/ /' > $fw_updater_path/updater-script
            $header
            assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")));
            $fw_lines
            show_progress(0.100000, 10);
            run_program("/system/bin/bootctl", "set-active-boot-slot", "0");
            set_progress(1.000000);
EOF
        unset fw_lines
        ln -n bin/aarch64-linux-gnu/update-binary $fw_updater_path
     ;;
    esac
    ln -n bin/aarch64-linux-gnu/update-binary $rom_updater_path
    cat <<EOF | sed 's/^ *//g; s/^$/ /' > $rom_updater_path/updater-script
        $header
        $fw_lines
        assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")));
        $partition_lines
EOF
    cat <<EOF | sed 's/^ *//g' >> $rom_updater_path/updater-script
             show_progress(0.100000, 10); 
             run_program("/system/bin/bootctl", "set-active-boot-slot", "0"); 
             set_progress(1.000000);
EOF
    printf "\n\n\e[1m\e[37m%s\e[0m\n\n" " Creating dynamic partition list..."
    cat <<EOF | sed 's/^ *//g' >> ${OUT}dynamic_partitions_op_list
             remove_all_groups
             add_group qti_dynamic_partitions_a 9122611200
             add_group qti_dynamic_partitions_b 9122611200
             add system_a qti_dynamic_partitions_a
             add system_b qti_dynamic_partitions_b
             add system_ext_a qti_dynamic_partitions_a
             add system_ext_b qti_dynamic_partitions_b
             add product_a qti_dynamic_partitions_a
             add product_b qti_dynamic_partitions_b
             add vendor_a qti_dynamic_partitions_a
             add vendor_b qti_dynamic_partitions_b
             add odm_a qti_dynamic_partitions_a
             add odm_b qti_dynamic_partitions_b
             resize system_a $SYSTEM
             resize system_ext_a $SYSTEMEXT
             resize product_a $PRODUCT
EOF
    case $mode in
     1)
      cat <<EOF | sed 's/^ *//g' >> ${OUTFW}dynamic_partitions_op_list
             remove vendor_a
             remove vendor_b
             add vendor_a qti_dynamic_partitions_a
             add vendor_b qti_dynamic_partitions_b
             resize vendor_a $VENDOR
EOF
     ;;
     0)
      echo "resize vendor_a $VENDOR" >> ${OUT}dynamic_partitions_op_list
     ;;
    esac
    [ -f extracted/odm.img ] && echo "resize odm_a $ODM" >> ${OUT}dynamic_partitions_op_list
}

create_flashable(){
    printf "\n\e[32m%s\e[0m\n" " Waiting for image processes to be done"
    wait 
    create_zip_structure
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    printf "\e[1;32m%#$((COLUMNS/3+3))s %s %s %s\e[0m\n" "Creating" "flashable" "repack rom"
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    (( mode == 1 )) && {
        printf "\n\n\e[1m\e[37m%s\e[0m\n\n\n" "Packing firmware files..."
        cd $OUTFW
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext"-Step2.zip * -bso0
        printf "\n\n\e[1m\e[37m%s\e[0m\n\n" "Packing rom files..."
        cd ../rom
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext"-Step1.zip * -bso0
    } ||
    {
        printf "\n\n\e[1m\e[37m%s\e[0m\n\n" "Packing rom files..."
        cd $OUT
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name""$nameext".zip * -bso0
    }
    cd $HOME
    cleanup --deep
    printf "\e[1;32m%s\e[0m\n\n" "Your repacked rom is ready to flash. You can find it in /sdcard/Repacks/"
    exit
}

main(){
    [ -z $1 ] && workspace_setup && file_extractor || workspace_setup
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    echo
    get_image_size
    img_to_sparse
    patch_recovery
    patch_magisk
    get_image_size
    create_flashable
}

integrity_check
