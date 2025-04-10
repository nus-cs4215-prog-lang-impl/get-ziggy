fn one(){1}

fn foo(a: u32) {}

fn bar(a: i32, b: i32) {}

fn main(){
    show();
    foo(1);
    bar(one(), foo(1));

    {"HI"};

    let n = 5;
    if n < 0 {
        print("{} is negative", n);
    } else if n > 0 {
        print("{} is positive", n);
    } else {
        print("{} is zero", n);
    }

    1 + 2;
    true == false;
    3 > 2;
    (1+2) == (3*12);
    (3>2) && ((1 + 2) < 1);

    let x = 1;
    let mut y = 2;
    let b = 3_i32;

    "hello";
    'a';
    1;
    3.14;
    true;
    123u32;
    123_u32;

    let mut a = 0;
    while a < 10 {
        a += 1;
    }

    a;
    foo;

    a?;

    &x;
    &&y;
    & mut x;
    && mut y;
    * x;
    !true;
    -1;

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
