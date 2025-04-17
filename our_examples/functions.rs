fn one(){1}

fn foo(a: u32) {}

fn bar(a: i32, b: i32) {}

// fn foobar(a: i32, b: i32) -> i32 {}

fn main(){
    show();
    foo(1);
    bar(one(), foo(1));
}
