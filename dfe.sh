#!/bin/sh
path=$1

fsqcom=$path"etc/fstab.qcom"
fssm8250=$path"etc/fstab.sm8250"

start(){
    sed -i 's|,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0||' $fstabOneExt
    sed -i 's|,metadata_encryption=aes-256-xts:wrappedkey_v0||' $fstabOneExt
    sed -i 's|,keydirectory=/metadata/vold/metadata_encryption||' $fstabOneExt
    sed -i 's|,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized||' $fstabOneExt
    sed -i 's|,encryptable=aes-256-xts:aes-256-cts:v2+_optimized||' $fstabOneExt 
    sed -i 's|,encryptable=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0||' $fstabOneExt 
    sed -i 's|,quota||' $fstabOneExt 
    sed -i 's|inlinecrypt||' $fstabOneExt 
    sed -i 's|,wrappedkey||' $fstabOneExt 
}

if [ -f $fsqcom ] && [ -f $fssm8250 ]
then
    fstabOneExt="$fsqcom"
    start
    fstabOneExt="$fssm8250"
    start
    echo -e "\e[1;32m fstab.qcom and fstab.sm8250 have been succesfully patched for decryption.\e[0m"
elif [[ -f $fssm8250 ]]
then
    fstabOneExt="$fssm8250"
    start
    echo -e "\e[1;32m fstab.sm8250 has been succesfully patched for decryption.\e[0m"
elif [[ -f $fsqcom ]]
then
    fstabOneExt="$fsqcom"
    start
    echo -e "\e[1;32m fstab.qcom has been succesfully patched for decryption.\e[0m"
else
    echo -e "\e[1;31m Vendor patch for decryption has failed.\e[0m"
fi
exit 0