#!/data/local/autorepack/bin/bash
export PATH=$PWD/bin:$PATH
export LC_ALL=C
export TERMINFO=$PREFIX/share/terminfo/
export HOME=$PWD
mkdir -p /sdcard/Repacks

trap '{ kill -9 $(jobs -p); umount tmp; exit; } &> /dev/null;' EXIT INT
calc(){ awk 'BEGIN{ print int('"$1"') }'; }

print(){ printf "\e[1m\x1b[38;2;%d;%d;%dm%b\x1b[0m\n" 0x${1:0:2} 0x${1:2:2} 0x${1:4} "$2"; }

cleanup(){
    case $1 in
      --deep) rm -rf .magisk extracted/* output tmp/* .config;;
      --soft) rm -rf .magisk tmp/* output;; esac
}

integrity_check(){
    [[ $(printf extracted/*) == "extracted/*" ]] && { cleanup --deep; main; }
    for check in extracted/*.img; {
        case ${check##*/} in (system.img|product.img|system_ext.img|boot.img|vendor_boot.img)
            (( headcount++ ))
        esac
    }
    (( headcount != 5 )) && {
        dialog --stdout --title "Integrity Check" --msgbox \
            "There are some useless leftover .img files in the workspace. \
            They will be cleaned up." 6 50
        cleanup --deep
        main
    } || {
        dialog --stdout --yesno \
            "You already have some extracted img files in workspace. \
            Do you want to continue with them?" 6 50
        (( $? == 0 )) && cleanup --soft && main dirty || cleanup --deep && main
    }
}

workspace_setup(){
    [[ -f .config ]] || menu && [[ -f .config ]] || exit
    IFS=$':\n' read -d '\n' _ file _ name _ mode _ fw _ rw _ comp_level _ mm _ magisk _ addons < .config
    name=${name%.*}
    (( mm == 0 )) && unset magisk
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
    while (( ${current:=0} != 100 )); do
        chunk=$(du -sb $1 | cut -f1)
        current=$(calc "($chunk/$3)*100")
        echo $current
        echo "XXX"
        echo "‎"
        printf "Files are extracting: %s\n" $(ls -tc $1 | head -n 1)
        echo "XXX"
        read -t 1
     done | dialog  --title "$2" --gauge "" 7 70 0
}

reverse_extract(){
    mv tmp/*.img extracted/ 2> /dev/null || \
        { print c2195a "* Certain img files are missing, we'll have to quit" 1>&2; exit 1; }
    print d1d1d1 "Reverse engineering partition images..."
    while read file; do
        file=${file##*/}
        [[ ${file} == *.br ]] && { brotli -j -d tmp/${file}; file=${file/.br/}; }
        sdat2img tmp/${file%%.*}.transfer.list tmp/${file} extracted/${file%%.*}.img &> /dev/null
    done <<< "$(printf "%s\n" tmp/*.new.dat*)"
}

payload_extract(){
    paydump -c 8 -o extracted/ "$file" &> /dev/null &
    successbar extracted "Payload Image Extraction" $(paydump -l "$file" | tail -1)
    firmware_extract
}

firmware_extract(){
    rm -rf tmp/*
    [[ $fw == None ]] || {
        { 7za l "$fw" "*.img" -r | grep -q .img; } && {
            size=$(7za l "$fw" "*.img" -r | awk 'END{ print $3 }')
            7za e -otmp/ "$fw" "*.img" -r -y &> /dev/null &
            successbar tmp/ "Firmware Extraction"
        }
        mv tmp/* extracted/
    }
}

fastboot_extract(){
    echo
    { file tmp/super.img | grep -q sparse; } && {
        print d1d1d1 "Converting super.img to raw..."
        simg2img tmp/super.img extracted/super.img
        rm tmp/super.img
    }
    [[ $(printf tmp/*.img) != "tmp/*.img" ]] && mv tmp/*.img extracted/
    print d1d1d1 "Unpacking super..."
    lpunpack extracted/super.img extracted/
    rm extracted/super.img
    for file in extracted/*_a.img; { mv $file ${file%_a.img}.img; }
    rm -rf extracted/*_b.img extracted/rescue.img extracted/userdata.img extracted/dummy.img\
           extracted/persist.img extracted/metadata.img extracted/metadata.img
    firmware_extract
}

file_extractor(){
    case $file in
     *.tgz)
        print d1d1d1 "Retrieving information from archive..."
        rom_name=${file##*/}
        7za e "$file" -y -mmt8 -bso0 -bsp0 -o.
        size=$(7za l "${rom_name%.tgz}.tar" -ttar "*.img" -r -mmt8 | awk 'END{ print $4 }')
        7za e "${rom_name%.tgz}.tar" -y -bso0 -bsp0 -sdel -ttar "*.img" -r -mmt8 -otmp/ &
        successbar tmp "Fastboot Image Extraction" $size
        fastboot_extract && return
     ;;
     *.7z|*.zip|*.bin)
        [[ $file == *.bin ]] && payload_extract && return
        content=$(7za l "$file" payload.bin super.img "*.dat*" -r)
        { grep -q payload.bin <<< "$content";} && {
            size=$(7za l "$file" payload.bin | awk 'END{ print $4 }')
            7za e -otmp/ "$file" payload.bin -y -mmt8 &> /dev/null &
            successbar tmp "Payload.bin Extraction" $size
            file="tmp/payload.bin"
            payload_extract
            rm -rf tmp/* && return
        }
        { grep -q 'super.img' <<< "$content"; } && {
            size=$(7za l "$file" "*.img" -r | awk '/files/ { print $3 }')
            7za e "$file" -otmp/ "*.img" -y -r -mmt8 &> /dev/null &
            successbar tmp "Fastboot Image Extraction" $size
            fastboot_extract && return
        }
        { grep -q '.dat' <<< "$content"; } && {
            dialog --title "Warning" --stdout --yesno \
                "This ROM is already in a repacked state, \
                therefore no need repacking. Do you still want to continue?" 6 60
            (( $? == 1 )) && cleanup --deep && exit
            size=$(7za l "$file" "*.new.dat*" "*.transfer.list" "*.img" -r | awk '/files/ { print $3 }')
            7za e "$file" -otmp/ "*.new.dat*" "*.transfer.list" "*.img" -y -r -mmt8 &> /dev/null &
            successbar tmp "Reverse Repack Extraction" $size
            reverse_extract && return
        }
    esac
    print c2195a "You did not choose a valid ROM file" 1>&2 && exit 1
}

custom_magisk(){
    [[ -z $magisk ]] && return
    7za l "$magisk" lib/arm64-v8a/libmagiskboot.so | grep -q libmagiskboot.so && \
        arch="arm64-v8a" || arch="armeabi-v7a"
    rm -rf .magisk
    7za e -y -bso0 -bsp0 "$magisk" lib/${arch}/lib* \
         assets/{boot_patch,util_functions}.sh -o.magisk/

    for lib in .magisk/lib*; {
        lib=${lib%.so}
        mv ${lib}.so $lib
        mv $lib .magisk/${lib#*lib}
    }
    chmod -R +x .magisk
}

patch_recovery_magisk(){
    [[ $addons =~ Recovery || $addons =~ Magisk ]] || \
        { ln -n -f extracted/boot.img ${OUTFW}boot/boot.img; return; }
    read -t 1
    [[ -d .magisk ]] || cp -rf /data/adb/magisk/ .magisk
    ln -n -f extracted/boot.img .magisk/; echo
    cd .magisk || { print c2195a \
        "* Something went wrong with magisk folder, we can't seem to find it" 1>&2; exit 1; }
    [[ $addons =~ Recovery ]] && {
        print 62914a " Patching kernel with TWRP..."
        ./magiskboot unpack boot.img &> /dev/null
        7za e ../twrp/"$twrp" -so | 7za e -aoa -si -ttar -o. -bso0 -bsp0
        ./magiskboot cpio ramdisk.cpio sha1 &> /dev/null
        ./magiskboot repack boot.img &> /dev/null
        print 92cf74 " Recovery patch is done"
    }
    [[ $addons =~ Magisk ]] && {
        [[ -f new-boot.img ]] && mv new-boot.img boot.img
        print 62914a " Patching kernel with Magisk..."
        sh boot_patch.sh boot.img &> /dev/null
        print 92cf74 " Magisk patch is done"
    }
    cd ..
    mv .magisk/new-boot.img ${OUTFW}boot/boot.img
    rm -rf .magisk
}

patch_vendor(){
    [[ $addons =~ DFE ]] || return
    tune2fs -f -O ^read-only extracted/vendor.img &> /dev/null
    (( rw == 0 )) && grant_rw extracted/vendor.img &> /dev/null
    print d1d1d1 " Mounting vendor.img..."
    mountpoint -q tmp && umount tmp
    while (( ${count:=0} < 6 )); do
        (( count++ ))
        mount extracted/vendor.img tmp/ &> /dev/null
        mountpoint -q tmp && break
    done
    { mountpoint -q tmp; } && {
        print 92cf74 " Vendor image has temporarily been mounted"
        sed -i 's|fileencryption[^,]*,||g s|metadata_encryption[^,]*,||
               s|keydirectory[^,]*,||g s|,encryptable[^,]*,||g
               s|,quota|| s|inlinecrypt|| s|,wrappedkey||' tmp/etc/fstab* &> /dev/null \
                       || { print cee61e "* It is a strong possibility that \
                           vendor is corrupted, starting over is recommended" 1>&2; kill 0; }
        { grep -q 'keydirectory' tmp/etc/fstab*; } 2> /dev/null \
            && { print c2195a "* Vendor patch for decryption has failed" 1>&2; } \
            || { print 92cf74 " Vendor has been succesfully patched for decryption"; }
        umount tmp
    } || print c2195a "* Vendor image could not be mounted. Continuing without DFE patch" 1>&2
    (( rw == 0 )) && tune2fs -f -O read-only extracted/vendor.img &> /dev/null
}

get_image_size(){
    VENDOR=$(stat -c%s extracted/vendor.img) \
        || { print c2195a "* Vendor partition is missing" 1>&2; exit 1; }
    SYSTEM=$(stat -c%s extracted/system.img) \
        || { print c2195a "* System partition is missing" 1>&2; exit 1; }
    SYSTEMEXT=$(stat -c%s extracted/system_ext.img) \
        || { print c2195a "* System Ext partition is missing" 1>&2; exit 1; }
    PRODUCT=$(stat -c%s extracted/product.img) \
        || { print c2195a "* Product partition is missing" 1>&2; exit 1; }
    [[ -f extracted/odm.img ]] && ODM=$(stat -c%s extracted/odm.img)
    total=$(calc $VENDOR+$SYSTEM+$SYSTEMEXT+$PRODUCT+${ODM:=0})
}

grant_rw(){
    img_size=$(stat -c%s $1)
    new_size=$(calc $img_size*1.25/512)
    resize2fs -f $1 ${new_size}s
    e2fsck -y -E unshare_blocks $1
    resize2fs -f -M $1
    resize2fs -f -M $1
    
    img_size=$(stat -c%s $1)
    new_size=$(calc "($img_size+20*1024*1024)/512")
    resize2fs -f $1 ${new_size}s
}

multi_process_sparse(){
    file=${file##*/}
    [[ $file == system.img ]] && (( ODM < 1 )) && patch_boot --remove-avb
    [[ $file == vendor.img ]] && patch_vendor 1>&4 2>&5
    img2simg extracted/$file ${OUT}$file
    img2sdat ${OUT}$file -v4 -o $OUT -p ${file%.*}
    rm ${OUT}$file && \
    [[ $file == system.img ]] && (( comp_level > 0 )) && \
        brotli -$comp_level -j ${OUT}${file%.*}.new.dat
}

img_to_sparse(){
    print 62914a " Converting images in background\n"
    print d1d1d1 " Giving read and write permissions..."
    empty_space=$(calc 8788393472-$total)
    exec 4>&1; exec 5>&2;
    for file in extracted/*.img; {
        case ${file##*/} in system.img|product.img|system_ext.img|odm.img|vendor.img)
            (( rw == 1 )) && { tune2fs -l $file | grep -q 'shared_blocks' && grant_rw $file &> /dev/null; }
            (( SYSTEM > 4694304000 )) && { 
                case $mode in
                    0) (( comp_level < 1 )) && comp_level=5;;
                    1) (( comp_level < 1 )) && comp_level=2;; esac
                multi_process_sparse $file &> /dev/null &
                continue; }
            case ${file##*/} in
                odm.img) multi_process_sparse $file &> /dev/null & continue;;
                system.img) new_size=$(calc $SYSTEM+$empty_space/2);;
                *) new_size=$(calc $(stat -c%s $file)+$empty_space/2/3);; esac
            fallocate -l $new_size $file
            resize2fs -f $file &> /dev/null
            multi_process_sparse $file &> /dev/null &
        ;;
        vendor_boot.img|dtbo.img) ln -n -f $file ${OUTFW}boot/;;
        boot.img) continue ;;
        *) ln -n -f $file ${OUTFW}firmware-update/
        esac
    }
}

create_zip_structure(){
    [[ $name == None ]] && name="UnnamedRom"
    header=$(cat <<-EOF
				ui_print("*****************************");
				ui_print(" - ${name%%+*} by AutoRepack"); 
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
 
				package_extract_file("$root/$fw", "/dev/block/bootdevice/by-name/${fw%.img}_a");
				package_extract_file("$root/$fw", "/dev/block/bootdevice/by-name/${fw%.img}_b");
 
EOF
)
    }
    case $mode in 
     1)
        mv ${OUT}{vendor*,odm*,product*,system_ext*} $OUTFW
        cat <<-EOF > $fw_updater_path/updater-script
			$header
			$fw_lines
			assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")));
            $(sed -n '/. *Flashing system_a.*/{xNNN;d}p' <<< "$partition_lines")
			show_progress(0.100000, 10);
			run_program("/system/bin/bootctl", "set-active-boot-slot", "0");
			set_progress(1.000000);
EOF
        unset fw_lines
        partition_lines=$(sed -n '/. *Flashing system_a.*/{NNN;p}' <<< "$partition_lines")
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
    print d1d1d1 "\n\n Creating dynamic partition list...\n"
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
    print 62914a "\n Waiting for image processes to be done"
    wait 
    create_zip_structure
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    printf "\e[1;32m%#$((COLUMNS/3+26))s\e[0m\n" "Creating flashable repack rom"
    printf '\e[1;32m◼%.0s' $(seq 1 $COLUMNS)
    (( mode == 1 )) && {
        print d1d1d1 "\n\nPacking firmware files...\n\n"
        cd $OUTFW || { print c2195a \
            "* Something went wrong with firmware output folder, we can't seem to find it" 1>&2; exit 1; }
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name"-Step1.zip * -bso0
        print d1d1d1 "\n\nPacking rom files...\n"
        cd ../rom || { print c2195a \
            "* Something went wrong with rom output folder, we can't seem to find it" 1>&2; exit 1; }
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name"-Step2.zip * -bso0
    } ||
    {
        print d1d1d1 "\n\nPacking rom files...\n"
        cd $OUT || { print c2195a \
            "* Something went wrong with rom output folder, we can't seem to find it" 1>&2; exit 1; }
        7za a -r -mx1 -sdel -mmt8 /sdcard/Repacks/"$name".zip * -bso0
    }
    cd $HOME
    cleanup --deep
    print 92cf74 "Your repacked rom is ready to flash. You can find it in /sdcard/Repacks/\n"
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
