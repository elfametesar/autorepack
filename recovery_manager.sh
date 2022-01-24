#!bin/bash
export PATH=$PWD/bin:$PATH
HOME=$PWD

calc(){ awk 'BEGIN{ print int('"$1"') }'; }

successbar(){
    while (( ${current:=0} != 100 )); do
        chunk=$(du -sb $1)
        current=$(calc "(${chunk//$'\t'*/}/$3)*100")
        printf "\n%d\nXXX\n%s\n%s: %s\nXXX" \
        	${current} "‎" "Files are extracting" $(ls -tc $1 | head -n 1)
        read -t 1
     done | dialog  --title "$2" --gauge "" 7 70 0
}

retrieve_list(){
    unset list i
    while IFS= read tar; do
        [[ -z $tar ]] && return
        list+=("${tar}" ""‎)
        (( i++ ))
    done <<< "$(find twrp -name *.tar.xz -exec basename {} .tar.xz \;)"
    }

import_recovery(){
    cp -rf /data/adb/magisk .magisk
    cd .magisk
    [[ -z $rename ]] && { rename=${input##*/}; rename=${rename%%.}.tar.xz; }
    echo -e "\e[0m\e[37mUnpacking recovery image\e[0m" 1>&2
    ./magiskboot unpack "$input" &> /dev/null
    echo -e "\e[0m\e[37mCreating recovery package\e[0m" 1>&2
    tar -cf - ramdisk.cpio | xz -1 -c - > "$rename"
    cd ..
    [[ ! -f .magisk/ramdisk.cpio ]] && echo -e "\e[0m\e[1;31mErrors occured, aborting\e[0m" 1>&2 \
        && rm -rf .magisk && sleep 1 && return 1
    mv .magisk/"$rename" twrp/
    echo -e "\e[0m\e[37mCleaning up the workspace\e[0m" 1>&2
    rm -rf .magisk
    }

remove_recovery(){
    retrieve_list
    [[ -z $list ]] && return
    sel=$(dialog --stdout --no-cancel --title "Select Recovery" \
         --menu "Select the recovery you want to remove:" 0 0 0 "${list[@]}" "Return" ‎)
    [[ $sel == "Return" ]] && return
    rm twrp/"${sel}".tar.xz
    remove_recovery
}

select_recovery(){
    retrieve_list
    sel=$(dialog --stdout --title "Select Recovery" \
        --menu "Select the recovery you want to add:" 0 0 0\
        "${list[@]}" "Download Recovery" ‎ "Select from storage" ‎ "Remove a recovery" ‎)
    case $sel in
     Download*) dl=$(dialog --stdout --title "Select Recovery" \
         --menu "Select the recovery you want to download:" 0 0 0 \
         "Nebrassy 3.6" ‎ \
         "Vasi" ‎ \
         "Nebrassy 3.5" ‎ \
         "Teamwin Fork" ‎ \
         "SKK A11" ‎ \
         "SKK A12" ‎)
        (( $? == 0 )) && { rename_recovery; download_recovery; }
     ;;
     *storage*) input=$(dialog --stdout --title "USE SPACE TO SELECT FILES AND FOLDERS" --fselect /sdcard/ -1 -1)
        (( $? == 1 )) && return 
        [[ "$input" == *.img ]] && {
            rename_recovery
            import_recovery
        } || {
            echo -e "\e[0m\e[1;31mWrong file type\e[0m" 1>&2
            sleep 1
        }
     ;;
     Remove*) [[ -z $list ]] || remove_recovery;;
     *) echo "${sel}.tar.xz"; exit
    esac
    }

rename_recovery(){
    rename=$(dialog --stdout --inputbox "Do you want to rename the new recovery? Leave it blank for default value:" 10 50)
    [[ -z $rename ]] || rename+=.tar.xz
}

download_recovery(){
    rm -rf tmp/*
    case $dl in
        "Nebrassy 3.6") uri=(https://github.com/erenmete/uploads/raw/main/Nebrassy3.6.tar.xz "Nebrassy 3.6.tar.xz" 20245176);;
        "Vasi") uri=(https://github.com/erenmete/uploads/raw/main/Vasi.tar.xz "Vasi.tar.xz" 20683552);;
        "Nebrassy 3.5") uri=(https://github.com/erenmete/uploads/raw/main/Nebrassy3.5.tar.xz "Nebrassy3.5.tar.xz" 20355492);;
        "Teamwin Fork") uri=(https://github.com/erenmete/uploads/raw/main/TeamWin.tar.xz "Teamwin.tar.xz" 20271172);;
        "SKK A11") uri=(https://github.com/erenmete/uploads/raw/main/SKK-A11.tar.xz "SKK-A11.tar.xz" 36240260);;
        "SKK A12") uri=(https://github.com/erenmete/uploads/raw/main/SKK-A12.tar.xz "SKK-A12.tar.xz" 36376168);; esac
    curl -L -s ${uri[0]} -o tmp/"${uri[1]}" &> /dev/null &
    successbar tmp "Recovery Downloader" ${uri[2]}
    mv tmp/* twrp/"$rename"
    retrieve_list
}

while true; do
    select_recovery
done
exit