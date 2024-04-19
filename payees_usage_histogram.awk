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
    for (line in f) {
     if (f[line] ~ /<PAYEE /) {
         match(f[line], /id="([^"]+)"/, pi_arr)
         match(f[line], /name="([^"]*)"/, py_arr)
         payee[pi_arr[1]] = escape_special_characters(py_arr[1])
     }
    }

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

   print("Payee: Count -> Name")
   for (pid in payee_cnt){
       printf("%s: %i -> %s\n", pid, payee_cnt[pid], payee[pid])
   }
}
