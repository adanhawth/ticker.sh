#!/bin/bash
set -e

LANG=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8

SYMBOLS=("$@")

if ! $(type jq > /dev/null 2>&1); then
  echo "'jq' is not in the PATH. (See: https://stedolan.github.io/jq/)"
  exit 1
fi

if [ -z "$SYMBOLS" ]; then
  echo "Usage: ./ticker.sh AAPL MSFT GOOG BTC-USD"
  exit
fi

FIELDS=(symbol marketState regularMarketPrice regularMarketChange regularMarketChangePercent \
  preMarketPrice preMarketChange preMarketChangePercent postMarketPrice postMarketChange postMarketChangePercent dividendDate)
API_ENDPOINT="https://query1.finance.yahoo.com/v7/finance/quote?lang=en-US&region=US&corsDomain=finance.yahoo.com"

: "${COLOR_BOLD:=\e[1;37m}"
: "${COLOR_GREEN:=\e[32m}"
: "${COLOR_RED:=\e[31m}"
: "${COLOR_RESET:=\e[00m}"

symbols=$(IFS=,; echo "${SYMBOLS[*]}")
fields=$(IFS=,; echo "${FIELDS[*]}")

results=$(curl --silent "$API_ENDPOINT&fields=$fields&symbols=$symbols" \
  | jq '.quoteResponse .result')

query () {
  echo $results | jq -r ".[] | select (.symbol == \"$1\") | .$2"
}

for symbol in $(echo ${SYMBOLS[*]} | tr " " "\n" | sort -g); do
  if [ -z "$(query $symbol 'marketState')" ]; then
    printf 'No results for symbol "%s"\n' $symbol
    continue
  fi

  epochdivdate=$(query $symbol 'dividendDate')
  if [ "$epochdivdate" != "null" ]; then
    divdate=$(date +%Y%b%d -d @$epochdivdate | tr -s '[:lower:]' '[:upper:]')
  else
    divdate="NA"
  fi

  if [ $(query $symbol 'marketState') == "PRE" ] \
    && [ "$(query $symbol 'preMarketChange')" != "0" ] \
    && [ "$(query $symbol 'preMarketChange')" != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'preMarketPrice')
  elif [ $(query $symbol 'marketState') != "REGULAR" ] \
    && [ "$(query $symbol 'postMarketChange')" != "0" ] \
    && [ "$(query $symbol 'postMarketChange')" != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'postMarketPrice')
  else
    nonRegularMarketSign=''
    price=$(query $symbol 'regularMarketPrice')
  fi

  prevcloseprice=$(query $symbol 'regularMarketPreviousClose')
  diff=$(bc <<< "$price-$prevcloseprice")
  percent=$(bc -l <<< "($diff/$prevcloseprice)*100")

  if [ "$diff" == "0" ]; then
    color=
  elif ( echo "$diff" | grep -q ^- ); then
    color=$COLOR_RED
  else
    color=$COLOR_GREEN
  fi

  printf "%-10s$COLOR_BOLD%8.2f$COLOR_RESET" $symbol $price
  printf "$color%10.2f%12s$COLOR_RESET" $diff $(printf "(%.2f%%)" $percent)
  printf " %s" "$nonRegularMarketSign"
  printf "\t%s\n" $divdate
done
