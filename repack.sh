#!/data/local/autorepack/bin/bash

export PATH=$PWD/bin:$PATH
export LC_ALL=C
export TERMINFO=$PREFIX/share/terminfo/
export HOME=$PWD
mkdir -p /sdcard/Repacks

trap '{ kill -9 $(jobs -p); umount tmp; exit; } &> /dev/null;' EXIT INT

calc(){ awk 'BEGIN{ print int('"$1"') }'; }

cleanup(){
    case $1 in
      --deep) rm -rf .magisk extracted/* output tmp/* .conf;;
      --soft) rm -rf .magisk tmp/* output;; esac
}

integrity_check(){
    find extracted/ -type f | grep -q '.img' || { cleanup --deep; main; }
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
    } || {
        dialog --stdout --yesno \
            "You already have some extracted img files in workspace. Do you want to continue with them?" 6 50
        (($? == 0)) && cleanup --soft && main dirty || cleanup --deep && main
    }
}

workspace_setup(){
    [[ -f .conf ]] || menu && [[ -f .conf ]] || exit
    IFS="|" read file name mode fw rw comp_level mm magisk addons <<< "$(awk -F ': ' 'ORS="|" {print $2}' .conf)"
    name=${name%.*}
    ((mm == 0)) && unset magisk
    (( comp_level > 9 )) && comp_level="-best"
    case $mode in
        0) OUT="./output/ModeOne/"; OUTFW="./output/ModeOne/"; mkdir -p $OUT;;
        1) OUT="./output/ModeTwo/rom/"; OUTFW="./output/ModeTwo/fw/"; mkdir -p $OUT $OUTFW;; esac
    while read -d ", "; do
        case $REPLY in
            *Magisk*) name+="+Magisk" && custom_magisk;;
            *Recovery*) name+="+Recovery" \
                && while [[ -z "$twrp" ]]; do twrp=$(sh recovery_manager.sh); done;;
            *DFE*) name+="+DFE";; esac; done <<< "${addons},"
    name+="_repack"
    rom_updater_path="${OUT}META-INF/com/google/android"
    fw_updater_path="${OUTFW}META-INF/com/google/android"
    mkdir -p ${OUTFW}boot $rom_updater_path
    mkdir -p $fw_updater_path ${OUTFW}firmware-update ${OUTFW}boot
}

successbar(){
    while ((${current:=0} != 100)); do
        chunk=$(du -sb "$1" | cut -f1)
        current=$(calc "($chunk/$3)*100")
        echo "$current"
        echo "XXX"
        echo "‎"
        printf "Files are extracting: %s\n" "$(ls -tc "$1" | head -n 1)"
        echo "XXX"
        sleep 1
     done | dialog  --title "$2" --gauge "" 7 70 0
}

reverse_extract(){
    mv tmp/*.img extracted/ 2> /dev/null || { printf "\e[1;31m%s\e[0m\n" "* Certain img files are missing, we'll have to quit" 1>&2; exit 1; }
    printf "\e[37m%s\e[0m\n" "Reverse engineering partition images..."
    while read file; do
        [[ ${file} == *.br ]] && { brotli -j -d tmp/${file}; file=${$file/.br/}; }
        sdat2img tmp/${file%%.*}.transfer.list tmp/${file} extracted/${file%%.*}.img &> /dev/null
    done <<< "$(find tmp/ -type f -name "*.new.dat*" -printf "%f\n")"
}

payload_extract(){
    paydump -c 8 -o extracted/ "$file" &> /dev/null &
    successbar extracted "Payload Image Extraction" "$(paydump -l "$file" | tail -1)"
    firmware_extract
}

firmware_extract(){
    rm -rf tmp/*
    [[ $fw == None ]] || {
        { 7za l "$fw" "*.img" -r | grep -q .img; } && {
            7za e -otmp/ "$fw" "*.img" -r -y &> /dev/null &
            successbar tmp/ "Firmware Extraction" "$(7za l "$fw" "*.img" -r | awk 'END{ print $3 }')"
        }
        mv tmp/* extracted/
    }
}

fastboot_extract(){
    echo
    { file tmp/super.img | grep -q sparse; } && {
        printf "\e[37m%s\e[0m\n" "Converting super.img to raw..."
        simg2img tmp/super.img extracted/super.img
        rm tmp/super.img
    }
    find tmp/ -type f | grep -q .img && mv tmp/*.img extracted/
    printf "\e[37m%s\e[0m\n" "Unpacking super..."
    lpunpack extracted/super.img extracted/
    rm extracted/super.img
    for file in extracted/*_a.img; { mv "$file" "${file%%_a.img}".img; }
    rm -rf extracted/*_b.img extracted/rescue.img extracted/userdata.img extracted/dummy.img\
           extracted/persist.img extracted/metadata.img extracted/metadata.img
    firmware_extract
}

file_extractor(){
    case $file in
     *.tgz)
        printf "\e[37m%s\e[0m\n" "Retrieving information from archive..."
        rom_name=${file##*/}
        7za e "$file" -y -mmt8 -bso0 -bsp0 -o. && \
            size=$(7za l "${rom_name%.tgz}.tar" -ttar "*.img" -r -mmt8 | awk 'END{ print $4 }')
        7za e "${rom_name%.tgz}.tar" -y -bso0 -bsp0 -sdel -ttar "*.img" -r -mmt8 -otmp/ &
        successbar tmp "Fastboot Image Extraction" "$size"
        fastboot_extract && return
     ;;
     *.7z|*.zip|*.bin)
        [[ $file == *.bin ]] && payload_extract && return
        content=$(7za l "$file" payload.bin super.img "*.dat*" -r)
        { grep -q payload.bin <<< "$content";} && {
            7za e -otmp/ "$file" payload.bin -y -mmt8 &> /dev/null &
            successbar tmp "Payload.bin Extraction" \
                              "$(7za l "$file" payload.bin | awk 'END{ print $4 }')"
            file=tmp/payload.bin
            payload_extract
            rm -rf tmp/* && return
        }
        { grep -q 'super.img' <<< "$content"; } && {
            7za e "$file" -otmp/ "*.img" -y -r -mmt8 &> /dev/null &
            successbar tmp "Fastboot Image Extraction" \
                    "$(7za l "$file" "*.img" -r | grep "files" | awk '{ print $3 }')"
            fastboot_extract && return
        }
        { grep -q '.dat' <<< "$content"; } && {
            dialog --title "Warning" --stdout --yesno \
                "This ROM is already in a repacked state, therefore no need repacking. Do you still want to continue?" 6 60
            (($? == 1 )) && cleanup --deep && exit
            7za e "$file" -otmp/ "*.new.dat*" "*.transfer.list" "*.img" -y -r -mmt8 &> /dev/null &
            successbar tmp "Reverse Repack Extraction" \
                    "$(7za l "$file" "*.new.dat" "*.transfer.list" "*.img" -r | grep "files" | awk '{ print $3 }')"
            reverse_extract && return
        }
    esac
    printf "\e[1;31m%s\e[0m\n" "You did not choose a valid ROM file" 1>&2 && exit 1
}

custom_magisk(){
    [[ -z $magisk ]] && return
    7za l "$magisk" lib/arm64-v8a/libmagiskboot.so | grep -q libmagiskboot.so && \
        arch="arm64-v8a" || arch="armeabi-v7a"
    rm -rf .magisk && mkdir -p .magisk/chromeos
    7za e -y -bso0 -bsp0 "$magisk" lib/${arch}/lib* \
                                      assets/boot_patch.sh \
                                      assets/util_functions.sh -o.magisk/

    for lib in .magisk/lib*; {
        lib=${lib%.so}
        mv "${lib}".so "$lib"
        mv "$lib" .magisk/"${lib#*lib}"
    }
    chmod -R +x .magisk
}

patch_recovery_magisk(){
    [[ $addons =~ Recovery || $addons =~ Magisk ]] || { ln -n -f extracted/boot.img ${OUTFW}boot/boot.img; return; }
    [[ -d .magisk ]] || cp -rf /data/adb/magisk/ .magisk
    ln -n -f extracted/boot.img .magisk/
    cd .magisk || { printf "\e[1;31m%s\e[0m\n" "* Something went wrong with magisk folder, we can't seem to find it" 1>&2; exit 1; }
    [[ $addons =~ Recovery ]] && {
        printf "\e[32m%s\e[0m\n" " Patching kernel with TWRP..."
        ./magiskboot unpack boot.img &> /dev/null
        7za e ../twrp/"$twrp" -so | 7za e -aoa -si -ttar -o. -bso0 -bsp0
        ./magiskboot cpio ramdisk.cpio sha1 &> /dev/null
        ./magiskboot repack boot.img &> /dev/null
        printf "\e[1m\e[1;32m%s\e[0m\n" " Recovery patch is done"
    }
    [[ $addons =~ Magisk ]] && {
        [[ -f new-boot.img ]] && mv new-boot.img boot.img
        printf "\e[32m%s\e[0m\n" " Patching kernel with Magisk..."
        sh boot_patch.sh boot.img &> /dev/null
        printf "\e[1m\e[1;32m%s\e[0m\n" " Magisk patch is done"
    }
    cd ..
    mv .magisk/new-boot.img ${OUTFW}boot/boot.img
    rm -rf .magisk
}

patch_vendor(){
    [[ $addons =~ DFE ]] || return
    tune2fs -f -O ^read-only extracted/vendor.img &> /dev/null
    (( rw == 0 )) && grant_rw extracted/vendor.img &> /dev/null
    printf "\e[1m\e[1;37m%s\e[0m\n" " Mounting vendor.img..."
    mountpoint -q tmp && umount tmp
    while (( ${count:=0} < 6 )); do
        (( count++ ))
        mount extracted/vendor.img tmp/ &> /dev/null
        mountpoint -q tmp && break
    done
    { mountpoint -q tmp; } && {
        printf "\e[1;32m%s\e[0m\n" " Vendor image has temporarily been mounted"
        sed -i 's|,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0||
                   s|,metadata_encryption=aes-256-xts:wrappedkey_v0||
                   s|,keydirectory=/metadata/vold/metadata_encryption||
                   s|,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized||
                   s|,encryptable=aes-256-xts:aes-256-cts:v2+_optimized||
                   s|,encryptable=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0||
                   s|,quota||;
                   s|inlinecrypt||;
                   s|,wrappedkey||' tmp/etc/fstab* &> /dev/null || { printf "\e[1;33m%s\n\e[0m" \
                       "* It is a strong possibility that vendor is corrupted, starting over is recommended" 1>&2; exit 4; }
        { grep -q 'keydirectory' tmp/etc/fstab*; } \
            && { printf "\e[1;31m%s\n\e[0m" "* Vendor patch for decryption has failed" 1>&2; exit 1; } \
            || { printf "\e[1;32m%s\n\e[0m" " Vendor has been succesfully patched for decryption"; }
        umount tmp
    } || printf "\e[1;31m%s\e[0m\n" "* Vendor image could not be mounted. Continuing without DFE patch" 1>&2
    (( rw == 0 )) && tune2fs -f -O read-only extracted/vendor.img &> /dev/null
}

get_image_size(){
    VENDOR=$(stat -c%s extracted/vendor.img) || { printf "\e[1;31m%s\e[0m\n" "* Vendor partition is missing" 1>&2; exit 3; }
    SYSTEM=$(stat -c%s extracted/system.img) || { printf "\e[1;31m%s\e[0m\n" "* System partition is missing" 1>&2; exit 3; }
    SYSTEMEXT=$(stat -c%s extracted/system_ext.img) || { printf "\e[1;31m%s\e[0m\n" "* System Ext partition is missing" 1>&2; exit 3; }
    PRODUCT=$(stat -c%s extracted/product.img) || { printf "\e[1;31m%s\e[0m\n" "* Product partition is missing" 1>&2; exit 3; }
    [[ -f extracted/odm.img ]] && ODM=$(stat -c%s extracted/odm.img)
    total=$(calc "$VENDOR"+"$SYSTEM"+"$SYSTEMEXT"+"$PRODUCT"+"${ODM:=0}")
}

grant_rw(){
    img_size=$(stat -c%s "$1")
    new_size=$(calc "$img_size"*1.25/512)
    resize2fs -f "$1" "${new_size}"s
    e2fsck -y -E unshare_blocks "$1"
    resize2fs -f -M "$1"
    resize2fs -f -M "$1"
    
    img_size=$(stat -c%s "$1")
    new_size=$(calc "($img_size+20*1024*1024)/512")
    resize2fs -f "$1" "${new_size}"s
}

multi_process_sparse(){
    file=${file##*/}
    [[ $file == system.img ]] && (( ODM < 1 )) && patch_boot --remove-avb
    img2simg extracted/$file ${OUT}$file 4096
    img2sdat ${OUT}$file -v4 -o $OUT -p ${file%.*} 
    rm ${OUT}$file && \
    [[ $file == "system.img" ]] && (( comp_level > 0 )) && \
        brotli -$comp_level -j ${OUT}${file%.*}.new.dat
}

img_to_sparse(){
    printf "\n\e[1;32m%s\e[0m\n" " Converting images in background"
    printf "\e[1;37m%s\e[0m\n" " Giving read and write permissions..."
    empty_space=$(calc 8788393472-$total)
    for file in extracted/*.img; {
        case ${file##*/} in system.img|product.img|system_ext.img|odm.img|vendor.img)
            (( rw == 1 )) && { tune2fs -l "$file" | grep -q 'shared_blocks' && grant_rw "$file" &> /dev/null; } 
            [[ ${file##*/} == vendor.img ]] && patch_vendor
            (( SYSTEM > 4694304000 )) && { 
                case $mode in
                    0) (( comp_level < 1 )) && comp_level=4;;
                    1) (( comp_level < 1 )) && comp_level=2;; esac
                multi_process_sparse "$file" &> /dev/null &
                continue; }
            case ${file##*/} in
                odm.img) multi_process_sparse "$file" &> /dev/null & continue;;
                system.img) new_size=$(calc "$SYSTEM"+"$empty_space"/2);;
                *) new_size=$(calc "$(stat -c%s "$file")"+"$empty_space"/2/3);; esac
            fallocate -l "$new_size" "$file"
            resize2fs -f "$file" &> /dev/null
            multi_process_sparse "$file" &> /dev/null &
        ;;
        vendor_boot.img|dtbo.img) (( mode == 1 )) && ln -n -f "$file" ${OUTFW}boot/ && continue || \
             ln -n -f "$file" ${OUT}boot/ || continue;;
        boot.img) continue ;;
        *) ln -n -f "$file" ${OUTFW}firmware-update/
        esac
    }
    echo
}

create_zip_structure(){
    [[ $name == None ]] && name="UnnamedRom"
    header=$(cat <<-EOF
				ui_print("*****************************");
				ui_print(" - $name by AutoRepack"); 
				ui_print("*****************************");

				run_program("/sbin/busybox", "umount", "/system_root");
				run_program("/sbin/busybox", "umount", "/product");
				run_program("/sbin/busybox", "umount", "/system_ext");
				run_program("/sbin/busybox", "umount", "/odm");
				run_program("/sbin/busybox", "umount", "/vendor");

				package_extract_file("avbctl", "/tmp/");

				ui_print("Flashing partition images..."); 
EOF
)
    for partition in ${OUT}*.new.dat*; {
        partition=${partition##*/}
        partition_lines+=$(cat <<-EOF

		ui_print("Flashing ${partition%%.*}_a partition..."); 
		show_progress(0.100000, 0); 
		block_image_update(map_partition("${partition%%.*}_a"), package_extract_file("${partition%%.*}.transfer.list"), "$partition", "${partition%%.*}.patch.dat") || abort("E2001: Failed to flash ${partition%%.*}_a partition.");

EOF
)
    }
    for fw in ${OUTFW}firmware-update/* ${OUTFW}boot/*; {
        fw=${fw##*/}
        case $fw in boot.img|vendor_boot.img|dtbo.img)
            root="boot"
        ;;
        *)
            root="firmware-update"
        ;; esac
        fw_lines+=$(cat <<-EOF
 
				package_extract_file("$root/$fw", "/dev/block/bootdevice/by-name/${fw%%.img}_a");
				package_extract_file("$root/$fw", "/dev/block/bootdevice/by-name/${fw%%.img}_b");
 
EOF
)
    }
    case $mode in 
     1)
        fw_lines+=$(sed -n '/. *Flashing system_a.*/{xNNN;d}p' <<< "$partition_lines")
        partition_lines=$(sed -n '/. *Flashing system_a.*/{NNN;p}' <<< "$partition_lines")
        mv ${OUT}{vendor*,odm*,product*,system_ext*} $OUTFW
        cat <<-EOF > $fw_updater_path/updater-script
			$header
			assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")));
			$fw_lines
			show_progress(0.100000, 10);
			run_program("/system/bin/bootctl", "set-active-boot-slot", "0");
			set_progress(1.000000);
EOF
        unset fw_lines
        ln -n -f bin/aarch64-linux-gnu/update-binary $fw_updater_path
     ;;
    esac
    ln -n -f bin/aarch64-linux-gnu/update-binary $rom_updater_path
    cat <<-EOF > $rom_updater_path/updater-script
		$header
		$fw_lines
		assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")));
		$partition_lines

		run_program("/tmp/avbctl", "--force", "disable-verity");
		run_program("/tmp/avbctl", "--force", "disable-verification");

		show_progress(0.100000, 10); 
		run_program("/system/bin/bootctl", "set-active-boot-slot", "0"); 
		set_progress(1.000000);
EOF
    printf "\n\n\e[1m\e[37m%s\e[0m\n\n" " Creating dynamic partition list..."
    cat <<-EOF >> ${OUTFW}dynamic_partitions_op_list
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
			resize system_ext_a $SYSTEMEXT
			resize product_a $PRODUCT
			resize vendor_a $VENDOR
EOF
    echo "resize system_a $SYSTEM" >> ${OUT}dynamic_partitions_op_list
    [[ -f extracted/odm.img ]] && echo "resize odm_a $ODM" >> ${OUTFW}dynamic_partitions_op_list
}

create_flashable(){
    printf "\n\e[32m%s\e[0m\n" " Waiting for image processes to be done"
    wait 
    create_zip_structure
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    printf "\e[1;32m%#$((COLUMNS/3+26))s\e[0m\n" "Creating flashable repack rom"
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    (( mode == 1 )) && {
        printf "\n\n\e[1m\e[37m%s\e[0m\n\n\n" "Packing firmware files..."
        cd $OUTFW || { printf "\e[1;31m%s\e[0m\n" "* Something went wrong with firmware output folder, we can't seem to find it" 1>&2; exit 1; }
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name"-Step1.zip * -bso0
        printf "\n\n\e[1m\e[37m%s\e[0m\n\n" "Packing rom files..."
        cd ../rom || { printf "\e[1;31m%s\e[0m\n" "* Something went wrong with rom output folder, we can't seem to find it" 1>&2; exit 1; }
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name"-Step2.zip * -bso0
    } ||
    {
        printf "\n\n\e[1m\e[37m%s\e[0m\n\n" "Packing rom files..."
        cd $OUT || { printf "\e[1;31m%s\e[0m\n" "* Something went wrong with rom output folder, we can't seem to find it" 1>&2; exit 1; }
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name".zip * -bso0
    }
    cd "$HOME" || exit
    cleanup --deep
    printf "\e[1;32m%s\e[0m\n\n" "Your repacked rom is ready to flash. You can find it in /sdcard/Repacks/"
    exit
}

main(){
    [[ -z $1 ]] && workspace_setup && file_extractor || workspace_setup
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    echo
    get_image_size
    img_to_sparse
    patch_recovery_magisk
    get_image_size
    create_flashable
}

integrity_check
