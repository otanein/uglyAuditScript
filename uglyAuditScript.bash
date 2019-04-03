# !/bin/bash
# The Ugly Audit Script is maintained by agiannin@akamai.com - +33622777086

# This script has to be used with a hostname list you can get from https://control.akamai.com/cmportal/quickstart.jsp
# It outputs a formated text file with the following information : FQDN, HTTP Code, Redirected URL, Redirected URL HTTP code, Akamai CNAMEd, FastDNS

########################## Beginning of the script ##########################

# Test if the script has an argument

if [[ -z "$1" ]]; then
    echo -e "No input file supplied. Use the script as follow : ./uas.sh <path and name to your list file with its extension> \\nEx : ./uas_v1.0.sh customer_list.txt"
    exit 1
else

  # Variables declaration #
  # HOSTS list file
  # Number of hosts
  # Init counter at 0

HOSTS=$(cat "$1")
HOST_NB=$(cat "$1" |wc -l | sed "s/[^0-9]//g")
COUNT=0
RESULT="./uas_result.csv"

run()
{
    # Creating the result file and clearing the screen

        touch $RESULT
        printf "%s\n" "Hostname HTTPAnswerCode RedirectedURL RedirectedURLHTTPAnswerCode AkamaiCNAMED AkamaiDNS ZoneApexMapping" >> $RESULT
        clear

    # Loop for each line the input file

        for i in $HOSTS ; do

         APEX=0 # Set APEX to 0. If APEX reaches 2 at the end of the loop, then it is a ZAM hostname

        # Increase counter and display working hostname

          COUNT=$[COUNT + 1]
          echo -ne "Working on hostname : $i ($COUNT out of $HOST_NB)" \\r

        # Main functions #
        # HTTP code retrieval using curl with a 5 seconds timeout

          CODE_RET=$(curl -m 5 -s -o /dev/null -I -w "%{http_code}" $i)
          printf "$i $CODE_RET" >> $RESULT

          if [[ $CODE_RET = 301 ]] || [[ $CODE_RET = 302 ]]; then # Test if redirection (HTTP 301 or 302)
            REDIR_URL=$(curl -m 5 -Ls -o /dev/null -I -w "%{url_effective}" $i)  # Retrieve redirection url
            REDIR_CODE=$(curl -m 5 -s -o /dev/null -I -w "%{http_code}" $REDIR_URL)  # Retrieve the redirection URL HTTP code
            printf "%s" " $REDIR_URL $REDIR_CODE"  >> $RESULT
          else
            printf " - -" >> $RESULT
          fi

          # dig to test if we get an Akamai edge hostname

          dig +short a "$i" |grep -i 'akam\|edge' > /dev/null 2>&1 ;

        # If positive, (Akamai Edge hostname), then CNAMEd, else "-"

          if [[ $? -eq 0  ]]; then
            printf " CNAMEd" >> $RESULT
          else
            printf " -" >> $RESULT
            # AWK to get only the first IP address when dig is returning two addresses
            IP=$(dig +short a "$i" | awk 'BEGIN{ RS = "" ; FS = "\n" }{print $1}')
            # Regex to test it is a properly formatted IP address
            if [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                whois $IP |grep -i akamai > /dev/null 2>&1 ;
                    if [[ $? -eq 0  ]]; then
                        APEX=$[APEX +1]
                    fi
            fi
          fi

          # dig to test if the DNS server is an Akamai server (akam.net)

          dig +trace a "$i" |grep -i 'akam.net' > /dev/null 2>&1 ;

          # If positive (DNS akam.net), then "Yes, else "-"

          if [[ $? -eq 0  ]]; then
            printf " Yes " >> $RESULT
            APEX=$[APEX +1]
          else
            printf " - " >> $RESULT
          fi

          # If Apex is equal to 2, meaning the DNS is an *.akam.net and is the resolution does not provide a CNAME, then ZAM

          if [[ $APEX = 2 ]]; then
            echo "ZAM" >> $RESULT
          else
            echo "-" >> $RESULT
          fi

          clear

        done

        echo "The audit is done. Have fun!"
}

  # Test if a previous result file is present and ask the user if s/he wants to delete it and go on, or abort the script

  if [[ -e $RESULT ]]; then
    echo "Result file already exists, do you want to delete it? yes/no"
    read  ANSWER

    case "$ANSWER" in
    yes|y)
    rm $RESULT
    run
      ;;

    no|n)
      echo "Don't want to lose your precious results, right? Script aborted!"
      exit 0
      ;;
    *)
      echo "You have to select yes, y, no or n! Try again."
      exit 1
      ;;
    esac
  else
    run
  fi
fi

exit 0
