fn one() -> i32{1}

fn foo(a: i32) -> i32 {}

fn bar(a: i32, b: i32) {}

// fn foobar(a: i32, b: i32) -> i32 {}

fn main(){
    foo(1);
    bar(one(), foo(1));
}
