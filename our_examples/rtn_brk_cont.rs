fn main(){
    let mut a = 0;
    while a < 10 { 
        if (a % 2) == 1 {
            break;
        }
        a += 1;
    }
    a = 0;
    while a < 10 { 
        if (a % 2) == 1 {
            continue;
        }
        a += 1;
    }
    return a;
}
