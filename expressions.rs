use std::mem;

pub fn main(){
    1+1;
    "two";
    true;
    false;
    3.14;
    'c';
    1+1 == 2;

    // Variables
    let x = 5;
    x;
    // Mutable variable
    let mut y = 10;
    y += x + 5;  // Modifying a mutable variable
    y;

    // Blocks
    {
        let b = 10;
        b;
    }

    // Conditionals
    if x > 5 {
        y = 1;
    } else {
        y = -1;
    }
    // Conditionals: Expression
    let result = if x > 5 {
        "Greater"
    } else {
        "Smaller or equal"
    };

    // Pattern matching
    let number = 15;
    match number {
        1 => println!("One"),
        2 => println!("Two"),
        5 => println!("Five"),
        _ => println!("Some other number"),
    }

    // While loops
    let mut counter = 0;
    while counter < 5 {
        println!("c{}",counter);
        counter += 1;
    }

    // Calling functions
    private_function();
    public_function();

    // TODO: function ownership
    let xs: [i32; 5] = [1, 2, 3, 4, 5];
    xs[0];
    analyze_slice(& xs[1 .. 3]);
    // Negative space
    // xs[5];
}

fn private_function() {
    for i in 0..3 {
        println!("i{}",i);
    }
}

pub fn public_function() {
    2;
}

fn args_function(x: f64){
    return x + 1.;
}

fn analyze_slice(slice: &[i32]) {
    slice[0];
}
