#!/bin/sh

HOME=$PWD
PATH=$PWD/bin:$PATH

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
     echo "Downloading: $curfile"
     echo "XXX"
     done
     ) |
     dialog --stdout --title "$type" --gauge "" 6 70 0
}

retrieve_list(){
    unset list
    if [ ! -z "$(ls twrp/)" ]; 
    then
        i=1
        find twrp -type f -size -15M -delete &> /dev/null
        find twrp -type f ! -iname "*.tar.xz" -delete &> /dev/null
        for tar in $(ls twrp/ | tr -d '[:blank:]' | xargs -n 1 | xargs -I {} basename {} '.tar.xz'); do
            tar=$(echo $tar |awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
            list+=$i" $tar "
            let "i++"
        done
    else
        return
    fi
    }

add(){
    chmod +x aik/*  &> /dev/null
    aik/cleanup.sh &> /dev/null
    if [ -z "$rename" ]; then
        name=$(basename $(basename $input /) .img).tar.xz
    else
        name="$rename"
    fi
    echo -e "\e[0m\e[37mUnpacking recovery image\e[0m" >&2
    aik/unpackimg.sh "$input" &> /dev/null
    cd aik
    echo -e "\e[0m\e[37mCreating recovery package\e[0m" >&2
    tar -cf - ramdisk/ | xz -9 -c - > "$name"
    cd ../
    [ $(du -sm aik/$name | awk '{ print $1 }') -lt 15 ] && echo -e "\e[0m\e[1;31mErrors occured, aborting\e[0m" >&2 && aik/cleanup.sh &> /dev/null && sleep 2 && return 1
    mv "aik/$name" twrp/ 
    echo -e "\e[0m\e[37mCleaning up the workspace\e[0m" >&2
    aik/cleanup.sh &> /dev/null
    return
    }

find_file(){
    iteration=0
    ls twrp/|while read rec;
    do
        let "iteration++"
        [ -z "$(ls twrp/)" ] && return 
        if [ "$sel" == "$iteration" ]; then
            echo "$rec"
        fi
    done
}

remove(){
    retrieve_list; [ -z "$list" ] && return
    sel=$(dialog --stdout --no-cancel --title "Select Recovery" --menu "Select the recovery you want to remove:" 0 0 0 $list - "Return")
    if [ "$sel" == "-" ]
    then
        return
    else
        found=$(find_file)
        rm twrp/$found
        remove
    fi
}

select_recovery(){
    retrieve_list
    sel=$(dialog --stdout --title "Select Recovery" --menu "Select the recovery you want to add:" 0 0 0 $list - "Download recovery" + "Select from storage" ! "Remove a recovery")
    case $sel in
     "-") dl=$(dialog --stdout --title "Select Recovery" --menu "Select the recovery you want to download:" 0 0 0 \
         1 "Nebrassy" \
         2 "Vasi" \
         3 "Nebrassy Old" \
         4 "Teamwin Fork")
        [ "$?" == "0" ] && \
            rename_recovery && \
            download_recovery && \
            select_recovery || \
            select_recovery
     ;;
     "+") input=$(dialog --stdout --title "USE SPACE TO SELECT FILES AND FOLDERS" --fselect /sdcard/ -1 -1)
        [ "$?" == "1" ] && select_recovery 
        [[ "$input" == *.img ]] && \
            rename_recovery && \
            add || \
            echo -e "\e[0m\e[1;31mWrong file type\e[0m" >&2; \
            sleep 3; \
            select_recovery
     ;;
     "!") remove; select_recovery
     ;;
    esac
    find_file
    exit
    }

rename_recovery(){
    rename=$(dialog --stdout --inputbox "Do you want to rename the new recovery? Leave it blank for default value:" 10 50)
    [ "$?" == "1" ] && return 1
    [ -z "$rename" ] && unset rename || rename="$(echo $rename | tr -d ' ').tar.xz"
     }

download_recovery(){
    extractTo=tmp
    current=0.0
    rm -rf tmp/* &> /dev/null
    case $dl in
    1)
     fullsize=17096136
     curl -L -s https://github.com/erenmete/uploads/raw/main/nebrassy.tar.xz -o tmp/Nebrassy.tar.xz &> /dev/null &
     successbar 
    ;;
    2)
     fullsize=17259460
     curl -L -s https://github.com/erenmete/uploads/raw/main/vasi.tar.xz -o tmp/Vasi.tar.xz &> /dev/null &
     successbar 
    ;;
    3)
     fullsize=17215996
     curl -L -s https://github.com/erenmete/uploads/raw/main/nebrassyold.tar.xz -o tmp/Nebrassy3.5.tar.xz &> /dev/null &
     successbar 
    ;;
    4)
     fullsize=17121484
     curl -L -s https://github.com/erenmete/uploads/raw/main/teamwin.tar.xz -o tmp/Teamwin.tar.xz &> /dev/null &
     successbar 
    ;;
    esac
    [ ! -z "$rename" ] && mv tmp/$(ls tmp) twrp/$rename || mv tmp/* twrp/ &> /dev/null
    retrieve_list
    }

select_recovery
