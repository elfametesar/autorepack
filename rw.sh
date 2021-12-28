#dd if=/dev/zero bs=1M count=128 >> system.img
#e2fsck -f system.img
#resize2fs system.img
#blockdev --setrw system.img
#e2fsck -E unshare_blocks -y -f system.img
#resize2fs -f -M system.img
#e2fsck -y -E unshare_blocks system.img
#blockdev --setrw system.img

getCurrentSize(){
    currentSize=$($toy stat -c "%s" $1)
    currentSize=$(wc -c < $1)
    currentSizeMB=$(echo $currentSize | awk '{print int($1 / 1024 / 1024)}')
    currentSizeBlocks=$(echo $currentSize | awk '{print int($1 / 512)}')
    if [ -z "$2" ]; then
        printf "$app: Current size of $fiName in bytes: $currentSize\n"
        printf "$app: Current size of $fiName in MB: $currentSizeMB\n"
        printf "$app: Current size of $fiName in 512-byte sectors: $currentSizeBlocks\n\n"
    fi
}

shrink2Min(){
    printf "$app: Shrinking size of $fiName back to minimum size...\n"
    if ( ! resize2fs -f -M $1 ); then
        printf "$app: There was a problem shrinking $fiName. Please try again.\n\n"
        exit 1
    fi
}

increaseSize(){
    printf "$app: Increasing filesystem size of $fiName...\n"
    if ( ! resize2fs -f $1 $2"s" ); then
        printf "$app: There was a problem resizing $fiName. Please try again.\n\n"
        exit 1
    fi
}

addCustomSize(){
    getCurrentSize $1 1
    customSize=$(echo $currentSize $sizeValue | awk '{print $1 + ($2 * 1024 * 1024)}')
    customSizeMB=$(echo $customSize | awk '{print int($1 / 1024 / 1024)}')
    customSizeBlocks=$(echo $customSize | awk '{print int($1 / 512)}')
    printf "$app: Custom size of $fiName in bytes: $customSize\n"
    printf "$app: Custom size of $fiName in MB: $customSizeMB\n"
    printf "$app: Custom size of $fiName in 512-byte sectors: $customSizeBlocks\n\n"
    increaseSize $1 $customSizeBlocks
}

unshareBlocks(){
    printf "$app: 'shared_blocks feature' detected @ %s\n\n" $fiName
    newSizeBlocks=$(echo $currentSize | awk '{print ($1 * 1.25) / 512}')
    increaseSize $1 $newSizeBlocks
    printf "$app: Removing 'shared_blocks feature' of %s...\n" $fiName
    if ( ! e2fsck -y -E unshare_blocks $1 > /dev/null ); then
        printf "$app: There was a problem removing the read-only lock of %s. Ignoring\n\n" $fiName
    else
        printf "$app: Read-only lock of %s successfully removed\n\n" $fiName
    fi
    shrink2Min $1
}

makeRW(){
    fiName=${1//*\/}
    getCurrentSize $1
    features=`tune2fs -l $1 2>/dev/null | grep "feat"`
    if [ ! -z "${features:20}" ]; then
        if [[ "${features:20}" == *"shared_blocks"* ]]; then unshareBlocks $1; else printf "$app: NO 'shared_blocks feature' detected @ %s\n\n" $fiName; fi
        shrink2Min $1
        if [[ "$sizeValue" > 0 ]]; then
            addCustomSize $1
        fi
    fi
    printf "=================================================\n\n"
}
sizeValue=20
makeRW $1