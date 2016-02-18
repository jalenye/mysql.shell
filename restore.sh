#!/bin/sh
#
# 使用方法：
# ./restore.sh /增量备份父目录



#NOTE:恢复开始前请确保mysql服务停止以及数据和日志目录清空,如
# rm -rf /usr/local/mysql/innodb_data/*
# rm -rf /usr/local/mysql/data/*
# rm -rf /usr/local/mysql/mysql_logs/innodb_log/*


INNOBACKUPEX=innobackupex
INNOBACKUPEX_PATH=/usr/bin/$INNOBACKUPEX
TMP_LOG="/var/log/restore.$$.log"
MY_CNF=/etc/my.cnf
BACKUP_DIR=/root/backup # 你的备份主目录
FULLBACKUP_DIR=$BACKUP_DIR/full # 全库备份的目录
INCRBACKUP_DIR=$BACKUP_DIR/incre # 增量备份的目录
MEMORY=1024M # 还原的时候使用的内存限制数
ERRORLOG=`grep -i "^log-error" $MY_CNF |cut -d = -f 2`
MYSQLD_SAFE=/usr/bin/mysqld_safe
MYSQL_PORT=3306

#############################################################################


#显示错误


#############################################################################


error()
{
    echo "$1" 1>&2
    exit 1
}


#############################################################################


# 检查innobackupex错误输出


#############################################################################


check_innobackupex_fail()
{
    if [ -z "`tail -2 $TMP_LOG | grep 'completed OK!'`" ] ; then
    echo "$INNOBACKUPEX命令执行失败:"; echo
    echo "---------- $INNOBACKUPEX的错误输出 ----------"
    cat $TMP_LOG
    #保留一份备份的详细日志
    logfiledate=restore.`date +%Y%m%d%H%M`.txt
    cat $TMP_LOG>/root/backup/$logfiledate  
    rm -f $TMP_LOG
    exit 1
  fi
}


# 选项检测
if [ ! -x $INNOBACKUPEX_PATH ]; then
  error "$INNOBACKUPEX_PATH在指定路径不存在,请确认是否安装或核实链接是否正确."
fi


if [ ! -d $BACKUP_DIR ]; then
  error "备份目录$BACKUP_DIR不存在.请新建备份主目录$BACKUP_DIR"
fi



if [ $# != 1 ] ; then
  error "使用方法: $0 使用还原目录的绝对路径"
fi
  


if [ ! -d $1 ]; then
  error "指定的备份目录:$1不存在."
fi




PORTNUM00=`netstat -lnt|grep ${MYSQL_PORT}|wc -l`
if [ $PORTNUM00 = 1  ];
then
echo -e "\e[31m NOTE:------------------------------------------.\e[m" #红色
echo -e "\e[31m mysql处于运行状态,请关闭mysql. \e[m" #红色
echo -e "\e[31m NOTE:------------------------------------------.\e[m" #红色
exit 0
fi 


################判断还原增量备份部分还是所有################
ipname=''
read -p "输入截止增量备份名[默认所有]:" ipname
echo  
echo "输入截止增量备份名为:$ipname"



input_value=$1
intpu_res=`echo ${input_value%/*}` 




# Some info output
echo "----------------------------"
echo
echo "$0: MySQL还原脚本"
START_RESTORE_TIME=`date +%F' '%T' '%w`
echo "数据库还原开始于: $START_RESTORE_TIME"
echo






#PARENT_DIR=`dirname ${intpu_res}`
PARENT_DIR=${intpu_res}


if [ $PARENT_DIR = $FULLBACKUP_DIR ]; then
FULL=`ls -t $FULLBACKUP_DIR |head -1`
FULLBACKUP=${intpu_res}/$FULL
echo "还原完全备份:`basename $FULLBACKUP`"
echo


else

################判断还原增量备份部分还是所有################
if [ "$ipname" = '' ];then
	if [ $PARENT_DIR = $INCRBACKUP_DIR ]; then
	FULL=`ls -t $FULLBACKUP_DIR |head -1`
	FULLBACKUP=$FULLBACKUP_DIR/$FULL
		if [ ! -d $FULLBACKUP ]; then
		error "全备:$FULLBACKUP不存在."
		fi
	INCR=`ls -t $INCRBACKUP_DIR/$FULL/ |sort -nr | head -1 ` #查找最后一个增量备份文件
	echo "还原将从全备全备$FULL开始,到增量$INCR结束."
	echo
	echo "Prepare:完整备份..........."
	echo "*****************************"
	$INNOBACKUPEX_PATH --defaults-file=$MY_CNF --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP > $TMP_LOG 2>&1
	check_innobackupex_fail
   


	# Prepare增量备份集,即将增量备份应用到全备目录中,按照增量备份顺序即按照时间从旧到最新
	for i in `find $PARENT_DIR/$FULL -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n `;
	do


	#判断最新全备的lsn
	#check_full_file=`find $FULLBACKUP/ -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head  -1`
   
	check_full_lastlsn=$FULLBACKUP/xtrabackup_checkpoints
   
	fetch_full_lastlsn=`grep -i "^last_lsn" ${check_full_lastlsn} |cut -d = -f 2`


	######判断增量备份中第一个增量备份的LSN
	#check_incre_file=`find $PARENT_DIR/$FULL -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n |  head -1`
     
	check_incre_lastlsn=$PARENT_DIR/$FULL/$i/xtrabackup_checkpoints
     
	fetch_incre_lastlsn=`grep -i "^last_lsn" ${check_incre_lastlsn} |cut -d = -f 2`
	echo "完全备份$FULLBACKUP的LSN值:${fetch_full_lastlsn} "
	echo "增量备份$i的LSN值:${fetch_incre_lastlsn} "

		if [ "${fetch_incre_lastlsn}" -eq "${fetch_full_lastlsn}" ];then
		echo "*****************************************"
		echo "LSN相等,不需要prepare!"
		echo "*****************************************"
		echo
		break



	else
	echo "Prepare:增量备份集$i........"
	echo "*****************************"
	$INNOBACKUPEX_PATH --defaults-file=$MY_CNF --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP --incremental-dir=$PARENT_DIR/$FULL/$i > $TMP_LOG 2>&1
	check_innobackupex_fail
 
		if [ $INCR = $i ]; then
		break
	fi
    
fi 
######判断LSN
done

else
error "未知的备份类型"
  fi


else
FULL=`ls -t $FULLBACKUP_DIR |head -1`
FULLBACKUP=$FULLBACKUP_DIR/$FULL
echo "Prepare:完整备份..........."
echo "*****************************"
$INNOBACKUPEX_PATH --defaults-file=$MY_CNF --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP > $TMP_LOG 2>&1
check_innobackupex_fail





ipt=`stat -c=%Z  $PARENT_DIR/$FULL/$ipname |cut -d = -f 2`
echo "还原的指定增量目录文件$ipname的纪元时间为:$ipt"
for i in `find $PARENT_DIR/$FULL -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n `;
do
f01=`stat -c=%Z  $PARENT_DIR/$FULL/$i |cut -d = -f 2`
if [ "$f01" -le "$ipt" ]; then


if [ $PARENT_DIR = $INCRBACKUP_DIR ]; then
if [ ! -d $FULLBACKUP ]; then
error "全备:$FULLBACKUP不存在."
fi
#INCR=`ls -t $INCRBACKUP_DIR/$FULL/ |sort -nr | head -1`
echo "还原将从全备$FULL开始,到增量$ipname结束."
echo


#判断最新全备的lsn
#check_full_file=`find $FULLBACKUP/ -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head  -1`
   
check_full_lastlsn=$FULLBACKUP/xtrabackup_checkpoints
   
fetch_full_lastlsn=`grep -i "^last_lsn" ${check_full_lastlsn} |cut -d = -f 2`


######判断增量备份中第一个增量备份的LSN
check_incre_file=`find $PARENT_DIR/$FULL -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n |  head -1`
     
check_incre_lastlsn=$PARENT_DIR/$FULL/$i/xtrabackup_checkpoints
     
fetch_incre_lastlsn=`grep -i "^last_lsn" ${check_incre_lastlsn} |cut -d = -f 2`
echo "完全备份的LSN:${fetch_full_lastlsn} "
echo "增量备份的LSN:${fetch_incre_lastlsn} "
if [ "${fetch_incre_lastlsn}" -eq "${fetch_full_lastlsn}" ];then
echo "*****************************************"
echo "LSN不需要prepare!"
echo "*****************************************"
echo
break
else 
echo "Prepare:增量备份集$i........"
echo "*****************************"
$INNOBACKUPEX_PATH --defaults-file=$MY_CNF --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP --incremental-dir=$PARENT_DIR/$FULL/$i > $TMP_LOG 2>&1
check_innobackupex_fail

fi 

######判断LSN
check_full_lastlsn=$FULLBACKUP/xtrabackup_checkpoints
   
fetch_full_lastlsn=`grep -i "^last_lsn" ${check_full_lastlsn} |cut -d = -f 2`
echo "完全备份当前的LSN:${fetch_full_lastlsn}"


else
error "未知的备份类型"
fi
else 
echo "查找增量备份文件完成."
check_full_lastlsn=$FULLBACKUP/xtrabackup_checkpoints
   
fetch_full_lastlsn=`grep -i "^last_lsn" ${check_full_lastlsn} |cut -d = -f 2`
echo -e "\e[31m -------------------------------------------- \e[m" #红色
echo -e "\e[31m 完全备份最终的LSN:${fetch_full_lastlsn} \e[m" #红色
echo -e "\e[31m -------------------------------------------- \e[m" #红色
break
fi
done


fi
#################判断还原增量备份部分还是所有################



fi




echo 
echo "prepare:完整备份以及回滚那些未提交的事务..........."
$INNOBACKUPEX_PATH --defaults-file=$MY_CNF --apply-log --use-memory=$MEMORY $FULLBACKUP > $TMP_LOG 2>&1
check_innobackupex_fail




echo "*****************************"
echo "数据库还原中 ...请稍等"
echo "*****************************"


$INNOBACKUPEX_PATH --defaults-file=$MY_CNF --copy-back $FULLBACKUP > $TMP_LOG 2>&1
check_innobackupex_fail


  
rm -f $TMP_LOG
echo "1.恭喜,还原成功!."
echo "*****************************"




#修改目录权限
echo "修改mysql目录的权限."
mysqlcnf="/usr/local/mysql/my.cnf"
mysqldatadir=`grep -i "^basedir" $mysqlcnf |cut -d = -f 2`
`echo 'chown -R mysql:mysql' ${mysqldatadir}`
echo "2.权限修改成功!"
echo "*****************************"




#自动启动mysql


INIT_NUM=1
if [ ! -x $MYSQLD_SAFE ]; then
  echo "mysql安装时启动文件未安装到$MYSQLD_SAFE或无执行权限"
  exit 1  #0是执行成功,1是执行不成功
else
echo "启动本机mysql端口为:$MYSQL_PORT的服务"
$MYSQLD_SAFE --defaults-file=$MY_CNF  > /dev/null &
while  [ $INIT_NUM  -le 8 ]
      do
        PORTNUM=`netstat -lnt|grep ${MYSQL_PORT}|wc -l`
        echo "mysql启动中....请稍等..."
        sleep 5
        if [ $PORTNUM = 1  ];
        then
echo -e "\e[32m mysql                                      ****启动成功**** \e[m"
        exit 0
        fi  
        INIT_NUM=$(($INIT_NUM +1))
      done
echo -e "\e[31m mysql启动失败或启动时间过长,请检查错误日志 `echo 'cat ' ${ERRORLOG}` \e[m"
echo "*****************************************"
exit 0
fi








END_RESTORE_TIME=`date +%F' '%T' '%w`
echo "数据库还原完成于: $END_RESTORE_TIME"
exit 0
