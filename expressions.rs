fn main(){
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
}

fn private_function() {
    for i in 0..3 {
        println!("i{}",i);
    }
}

pub fn public_function() {
    2;
}

