# KMyMoney's XML to hledger/beancount's journal file converter
# License: GPL v3.0
# Author: Altynbek Isabekov

# Tested using GNU Awk 5.1.0

# Usage:
# awk -v rdac=[value] -v tub=[value] -f kmymoney2ledgers.awk [inputfile].xml > [output].[extension]
# Input flags:
#    -v tub=value          If value is 1, then use beancount journal output format.
#                          If value is 0 or flag is not specified, then output format is hledger journal.
#    -v rdac=value         If value is 1, then replace destination account commodity (currency) with source
#                          account commodity. No currency conversion is performed. Recommended option.
#                          If value is 0 or flag is not specified, then use currency conversion specified
#                          in the transaction split, i. e. how it is displayed in KMyMoney.

# Examples:
# Beancount output:
# awk -v rdac=1 -v tub=1 -f kmymoney2ledgers.awk [inputfile].xml > [output].beancount

# Hledger output:
# awk -v rdac=1 -v tub=0 -f kmymoney2ledgers.awk [inputfile].xml > [output].journal
# awk -v rdac=1 -f kmymoney2ledgers.awk [inputfile].xml > [output].journal

# Default options: rdac=0, tub=0, so the following two commands will produce the same output:
# awk -v rdac=0 -v tub=0 -f kmymoney2ledgers.awk [inputfile].xml > [output].journal
# awk -f kmymoney2ledgers.awk [inputfile].xml > [output].journal

function traverse_account_hierarchy_backwards(child, tub){
    if (acnt_prnt[child] == ""){
        if (acnt_name[child] in AccountRenaming){
            name = AccountRenaming[acnt_name[child]]
        } else {
            name = tub ? gensub(/[[:punct:] ]/, "-", "g", acnt_name[child]) : acnt_name[child]
        }
        return tub ? gensub(/[[:punct:] ]/, "-", "g", name): name
    } else {
        parent_acnt_name = traverse_account_hierarchy_backwards(acnt_prnt[child], tub)
        name = tub ? gensub(/[[:punct:] ]/, "-", "g", acnt_name[child]) : acnt_name[child]
        return parent_acnt_name ":" name
    }
}

function abs(value){
    return (value < 0 ? -value : value)
}


BEGIN {
    AccountRenaming["Asset"] = "Assets"
    AccountRenaming["Liability"] = "Liabilities"
    AccountRenaming["Expense"] = "Expenses"

    Categories["12"] = "Income"
    Categories["13"] = "Expense"

    # Replace destination account currency flag
    rdac = (rdac == "") ? 0 : rdac

    # To use Beancount output or not
    tub = (tub == "") ? 0 : tub
}{
    # Main loop: read all lines into buffer
    f[i=1] = $0
    while (getline)
        f[++i] = $0
}
END {
   for (line in f) {
       if (f[line] ~ /<ACCOUNT /) {
           match(f[line], /id="([^"]+)"/, id_arr)
           match(f[line], /name="([^"]*)"/, nm_arr)
           match(f[line], /parentaccount="([^"]*)"/, pa_arr)
           match(f[line], /opened="([^"]*)"/, od_arr)
           match(f[line], /currency="([^"]*)"/, cur_arr)
           match(f[line], /type="([^"]*)"/, type_arr)
           acnt_name[id_arr[1]] = nm_arr[1]
           acnt_prnt[id_arr[1]] = pa_arr[1]
           acnt_opdt[id_arr[1]] = od_arr[1]
           acnt_curr[id_arr[1]] = cur_arr[1]
           acnt_type[id_arr[1]] = type_arr[1]
       }
       if (f[line] ~ /<PAYEE /) {
           match(f[line], /id="([^"]+)"/, pi_arr)
           match(f[line], /name="([^"]*)"/, py_arr)
           payee[pi_arr[1]] = py_arr[1]
       }
       if (f[line] ~ /kmm-baseCurrency/) {
           match(f[line], /value="([^"]+)"/, base_curr_arr)
           base_currency = base_curr_arr[1]
       }
       if (f[line] ~ /<TRANSACTIONS/) {
           match(f[line], /count="([^"]+)"/, txn_cnt_arr)
           txn_cnt_tot = txn_cnt_arr[1]
       }
       if (f[line] ~ /<TAGS/){
           while (f[line] !~/<\/TAGS/){
               if (f[line] ~/<TAG /){
                   match(f[line], /id="([^"]+)"/, tags_id_arr)
                   match(f[line], /name="([^"]+)"/, tags_name_arr)
                   tags[tags_id_arr[1]] = tags_name_arr[1]
               }
               line++
           }
       }
   }

   # Header for Beancount output
   if (tub){
       print "option \"title\" \"Personal Finances\""
       printf("option \"operating_currency\" \"%s\"\n", base_currency)
       printf("plugin \"beancount.plugins.implicit_prices\"\n\n")
   }

   # Opening dates of accounts for Beancount output
   for (id in acnt_name){
       acnt_full_name[id] = traverse_account_hierarchy_backwards(id, tub)
       if (tub){
           if (acnt_opdt[id] == "")
               open_dt = "1900-01-01"
           else
               open_dt = acnt_opdt[id]

           # Do not display parent account (i.e. accounts without ":" character in the name)
           if (match(acnt_full_name[id], /:/))
               printf "%s\n", open_dt " open " acnt_full_name[id] " ;" id
       }
   }

   # Transactions
   t = 0
   for (x in f) {
       if (f[x] ~ /<TRANSACTION /){
           # Increment transaction counter
           t++
           # Logging to display progress in the standard error stream
           if ((t % 1000 == 0) || (t == 1) || (t == 10) || (t == 100) || (t == txn_cnt_tot)){
               print "Processiong transaction", t, "out of", txn_cnt_tot > "/dev/stderr"
           }
           match(f[x], /id="([^"]+)"/, tr_id)
           match(f[x], /postdate="([^"]+)"/, post_date)
           # Date separator for hledger and beancount differ
           post_date_str = tub ? post_date[1] : gensub(/-/, "/", "g", post_date[1])
           match(f[x], /commodity="([^"]+)"/, txn_commodity)

           # Split counter. It should be reset to zero outside the while-loop.

           c = 0
           while(f[x] !~ /<\/TRANSACTION/){ # Till the end of transaction definition.
               if (f[x] ~ /<SPLIT /){
                  g = 0
                  ++c
                  match(f[x], /payee="([^"]+)"/, sp_payee)
                  sp_lst_payee[c] = sp_payee[1]

                  match(f[x], /account="([^"]+)"/, sp_acnt)
                  sp_lst_acnt[c] = sp_acnt[1]

                  match(f[x], /memo="([^"]+)"/, sp_memo)
                  sp_lst_memo[c] = sp_memo[1]

                  match(f[x], /value="([^"]+)"/, val_arr)
                  if (length(val_arr) != 0){
                      split(val_arr[1], val, "/")
                      if (val[2] == 0){
                          sp_lst_val[c] = val[1]
                      } else{
                          sp_lst_val[c] = val[1] / val[2]
                      }
                  }

                  match(f[x], /shares="([^"]+)"/, shares_arr)
                  if (length(shares_arr) != 0){
                      split(shares_arr[1], shares, "/")
                      if (shares[2] == 0){
                          sp_lst_shares[c] = shares[1]
                      } else{
                          sp_lst_shares[c] = shares[1] / shares[2]
                      }
                  }

                  match(f[x], /price="([^"]+)"/, price_arr)
                  if (length(price_arr) != 0){
                      split(price_arr[1], price, "/")
                      if (price[2] == 0){
                          sp_lst_price[c] = price[1]
                      } else{
                          sp_lst_price[c] = price[1] / price[2]
                      }
                  }
               }
               if (f[x] ~ /<TAG/){
                   g++
                   match(f[x], /id="([^"]+)"/, sp_tags_arr)
                   sp_lst_tags[c,g] = sp_tags_arr[1]
               }
               sp_slt_tag_cnt[c] = g
               x++
           }

           print "\n;", tr_id[1]

           # Concatenate tags for a split
           for (i=1; i <= c; i++){
               tags_concat[i] = " "
               for (j=0; j <= sp_slt_tag_cnt[i]; j++){
                   if (tags[sp_lst_tags[i,j]] != ""){
                       tags_concat[i] = sprintf("%s %s", tags_concat[i], tags[sp_lst_tags[i,j]]":")
                   }
               }
           }
           # Transaction level tags are defined only for transactions with 2 splits, one of which is empty.
           if (c==2){
               if ((tags_concat[1] == " ") && (tags_concat[2] == " ")){
                   txn_tags = ""
               } else {
                   # At least one split has tags
                   if (tags_concat[1] == ""){
                       txn_tags = tags_concat[2]
                   } else {
                       txn_tags = tags_concat[1]
                   }
                   txn_tags = sprintf(" Tags= %s", txn_tags)
               }
           } else {
               txn_tags = ""
           }
           delete sp_lst_tags
           printf("%s * \"%s\" ; %s%s\n", post_date_str, payee[sp_lst_payee[1]], sp_lst_payee[1], txn_tags)

           # Splits in a transaction
           for (i=1; i <= c; i++){
               sp_acnt_currency = acnt_curr[sp_lst_acnt[i]]
               sp_acnt_type = acnt_type[sp_lst_acnt[i]]

               cond_1 = txn_commodity[1] == sp_acnt_currency
               cond_2 = ((! cond_1) && rdac && (sp_acnt_type in Categories))

                if (cond_1 || cond_2){
                    # Destination account currency is replaced with source account currency and the destination amount
                    # is set to the negated source amount when:
                    # * source and destination accounts have the same currency, the destination account can be either
                    #   a "money" account or an "expense category",
                    # * source is a "money" account and destination is an "expense category" and the flag
                    # "rdac" is set to true.
                    printf("    %s  %.4f %s", acnt_full_name[sp_lst_acnt[i]], sp_lst_val[i], txn_commodity[1])
                } else {
                    # Keep the destination account currency as it is specified in the KMyMoney transaction when:
                    # * source is a "money" account and destination is an "expense category" and it was specified in
                    #   the input argument and the flag "rdac" (replace destination account currency) is set to false,
                    # * some amount of a foreign currency is bought, so conversion is necessary, since both source and
                    #   destination accounts are "money" accounts (inverse of cond_1).
                    printf( "    %s  %.4f %s @@ %.4f %s", acnt_full_name[sp_lst_acnt[i]], sp_lst_shares[i],
                            acnt_curr[sp_lst_acnt[i]], abs(sp_lst_val[i]), txn_commodity[1])
                }

                if (c != 2){
                    if (!sp_lst_memo[i]){
                        if (tags_concat[i] != " "){
                            printf("; Tags= %s\n", tags_concat[i])
                        } else {
                            printf("\n")
                        }
                    } else {
                        if (tags_concat[i] != " "){
                            printf("; %s;    Tags= %s\n", sp_lst_memo[i], tags_concat[i])
                        } else {
                            printf("; %s\n", sp_lst_memo[i])
                        }
                    }
                } else {
                    if (!sp_lst_memo[i]){
                        printf("\n")
                    } else {
                        printf("  ; %s\n", sp_lst_memo[i])
                    }
                }
           }
       }
   }

   # Prices of currencies
   for (x in f){
       if (f[x] ~ /<PRICEPAIR /){
           match(f[x], /from="([^"]+)"/, price_from_arr)
           price_from = price_from_arr[1]
           match(f[x], /to="([^"]+)"/, price_to_arr)
           price_to = price_to_arr[1]
           printf("\n;==== %s to %s  =====\n", price_from, price_to)
           while(f[x] !~ /<\/PRICEPAIR/){
               if (f[x] ~ /<PRICE/){
                   match(f[x], /date="([^"]+)"/, price_date_arr)
                   price_date = price_date_arr[1]
                   match(f[x], /price="([^"]+)"/, price_arr)
                   if (length(price_arr) != 0){
                       split(price_arr[1], price, "/")
                       if (price[2] == 0){
                           price_expr = price[1]
                       } else{
                           price_expr = price[1] / price[2]
                       }
                       if (tub){
                           printf("%s price %s %.4f %s\n", price_date, price_from, price_expr, price_to)
                       } else {
                           printf("P %s %s %.4f %s\n", gensub(/-/, "/", "g", price_date), price_from, price_expr, price_to)
                       }
                   }
               }
               x++
           }
       }
   }
}
