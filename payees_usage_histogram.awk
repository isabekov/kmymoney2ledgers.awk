function escape_special_characters(str, to_escape_back_slash){
    str = gensub(/&quot;/, "\"", "g", str)
    str = gensub(/&amp;/, "\\&", "g", str)
    str = gensub(/&lt;/, "<", "g", str)
    # Replace HTML-encoded tab with two whitespaces
    str = gensub(/&#x9;/, "  ", "g", str)
    # Replace HTML-encoded carriage return with two whitespaces
    str = gensub(/&#13;/, "  ", "g", str)
    return str
}

function replace_double_space_with_single_space(str){
    return gensub(/  /, " ", "g", str)
}

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

function parse_account_full_names(){
   for (id in acnt_name){
       acnt_full_name[id] = traverse_account_hierarchy_backwards(id, tub)
   }
}

function parse_dictionaries(){
   for (line in f) {
       if (f[line] ~ /<ACCOUNT .*opened.*/) {
           match(f[line], /id="([^"]+)"/, id_arr)
           match(f[line], /name="([^"]*)"/, nm_arr)
           match(f[line], /parentaccount="([^"]*)"/, pa_arr)
           match(f[line], /opened="([^"]*)"/, od_arr)
           match(f[line], /currency="([^"]*)"/, cur_arr)
           match(f[line], /type="([^"]*)"/, type_arr)
           # Double space in account name is not allowed
           acnt_name[id_arr[1]] = replace_double_space_with_single_space(nm_arr[1])
           acnt_name[id_arr[1]] = escape_special_characters(acnt_name[id_arr[1]], 0)
           acnt_prnt[id_arr[1]] = pa_arr[1]
           acnt_opdt[id_arr[1]] = od_arr[1]
           acnt_curr[id_arr[1]] = cur_arr[1]
           acnt_type[id_arr[1]] = type_arr[1]
       }
       if (f[line] ~ /<PAYEE /) {
           match(f[line], /id="([^"]+)"/, pi_arr)
           match(f[line], /name="([^"]*)"/, py_arr)
           payee[pi_arr[1]] = escape_special_characters(py_arr[1], tub)
       }
   }
}


BEGIN {
    PROCINFO["sorted_in"] = "@val_num_desc"
    AccountRenaming["Asset"] = "Assets"
    AccountRenaming["Liability"] = "Liabilities"
    AccountRenaming["Expense"] = "Expenses"

    Categories["12"] = "Income"
    Categories["13"] = "Expense"
}{
    # Main loop: read all lines into buffer
    f[i=1] = $0
    while (getline)
        f[++i] = $0
}
END {
    parse_dictionaries()
    parse_account_full_names()

    for (pid in payee){
        payee_cnt[pid] = 0
    }
   # Transaction counter
   t = 0
   # Scheduled transactions flag (do not convert them)
   st_flag = 0
   for (x in f) {
       if (f[x] ~ /<SCHEDULED_TX/){
           st_flag = 1
       }
       if (f[x] ~ /<\/SCHEDULED_TX/){
           st_flag = 0
       }
       if ((f[x] ~ /<TRANSACTION /) && (st_flag == 0)){
           # Increment transaction counter
           t++
           # Split counter. It should be reset to zero outside the while-loop.
           c = 0
           delete payee_cnt_at_txn
           while(f[x] !~ /<\/TRANSACTION/){ # Till the end of transaction definition.
               if (f[x] ~ /<SPLIT /){
                  g = 0
                  ++c
                  match(f[x], /payee="([^"]+)"/, sp_payee)
                  payee_cnt_at_txn[sp_payee[1]] +=1
               }
               x++
           }
           if (c == 2) {
               payee_cnt[sp_payee[1]] +=1
           } else {
               for (k in payee_cnt_at_txn){
                   payee_cnt[k] += 1
               }
           }
       }
   }

   print("Payee|Count|Name")
   for (pid in payee_cnt){
       printf("%s|%i|%s\n", pid, payee_cnt[pid], payee[pid])
   }
}
