// SPDX-License-Identifier: MIT
pragma solidity 0.8.16; // (10M optimization runs)

interface MonacoInterface {
    struct CarData {
        uint32 balance; // Where 0 means the car has no money.
        uint32 speed; // Where 0 means the car isn't moving.
        uint32 y; // Where 0 means the car hasn't moved.
        Car car;
    }

    function buyAcceleration(uint256 amount) external returns (uint256 cost);

    function buyShell(uint256 amount) external returns (uint256 cost);

    function getAccelerateCost(uint256 amount) external view returns (uint256 sum);

    function getShellCost(uint256 amount) external view returns (uint256 sum);

    function turns() external view returns (uint256 turn);
}


abstract contract Car {
    MonacoInterface internal immutable monaco;

    constructor(MonacoInterface _monaco) {
        monaco = _monaco;
    }

    // Note: The allCars array comes sorted in descending order of each car's y position.
    function takeYourTurn(MonacoInterface.CarData[] calldata allCars, uint256 yourCarIndex) external virtual;
}


/// @author 0age
/// @notice Be warned that this contract was hastily and iteratively hobbled together and has known bugs.
contract c000r is Car {
    constructor(MonacoInterface _monaco) Car(_monaco) {}

    function takeYourTurn(MonacoInterface.CarData[] calldata allCars, uint256 ourCarIndex) external override {
        MonacoInterface.CarData memory ourCar = allCars[ourCarIndex];

        // Win if possible.
        if (
            ourCar.y > 850 &&
            ourCar.balance >= monaco.getAccelerateCost(1000 - (ourCar.y + ourCar.speed))
        ) {
            monaco.buyAcceleration(1000 - (ourCar.y + ourCar.speed));
            return;
        }

        // Get the cost of a shell; only throw one per turn.
        uint256 shellCost = monaco.getShellCost(1);
        if (shellCost < 400 && ourCarIndex != 0 && allCars[0].y > 8 && allCars[1].y == 0 && allCars[2].y == 0) {
            // Respond to opening with a large move.
            monaco.buyShell(1);
            shellCost = 15001;
        } else if (shellCost == 0) {
            // Buy it if it's free.
            monaco.buyShell(1);
            shellCost = 15001;
        } else if (ourCarIndex == 1 && ourCar.balance >= shellCost && allCars[0].y + allCars[0].speed >= 1000) {
            // Don't lose if it can be stopped.
            ourCar.balance -= uint24(monaco.buyShell(1));
            shellCost = 15001;
        }
        
        // Handle early-game; hang back for a bit in hopes that other two players duke it out.
        if (ourCarIndex != 0 && allCars[0].y < 200) {
            // Only move if immobile and not paying gouged prices due to an opponent's big opening move.
            if (ourCar.speed < 3 && shellCost < 15000) {
                monaco.buyAcceleration(2);
            }
            
            return;
        }

        // Handle late-game cases.
        if (allCars[0].y > 850) {
            // Handle cases where speed is too low and we're in the lead.
            if (ourCarIndex == 0 && (allCars[1].speed > ourCar.speed) || allCars[2].speed > ourCar.speed) {
                uint256 largerSpeed = allCars[1].speed > allCars[2].speed ? allCars[1].speed : allCars[2].speed;
                if (ourCar.balance >= monaco.getAccelerateCost(largerSpeed - ourCar.speed)) {
                    monaco.buyAcceleration(largerSpeed - ourCar.speed);
                } else {
                    try monaco.buyAcceleration(5) {} catch {}
                }

                return;
            }

            // Handle cases where we're behind.
            if (ourCarIndex != 0) {
                uint256 frontCarSpeed = allCars[ourCarIndex - 1].speed;

                // Shell the car ahead if it's moving quickly.
                if (ourCar.balance >= shellCost && shellCost < 2000 && ((frontCarSpeed > ourCar.speed && frontCarSpeed > 4) || frontCarSpeed > 8)) {
                    ourCar.balance -= uint24(monaco.buyShell(1));
                    shellCost = 15001;
                }

                // Move forward decisively if we have the balance for it.
                uint256 bigMove = monaco.getAccelerateCost(7);
                if (ourCar.balance >= bigMove && bigMove < 1000) {
                    ourCar.balance -= uint24(monaco.buyAcceleration(7));
                    ourCar.speed += 7;
                }
            }
        }

        // Don't fall behind when in last place and get out of it late in the race.
        uint256 costToCatchUp = 0;
        if (ourCarIndex == 2) {
            if (allCars[1].balance < 200 || (allCars[0].y > 825 && allCars[1].y < 750)) {
                // try and get into second place in order to shell next turn.
                costToCatchUp = monaco.getAccelerateCost(1 + allCars[1].speed + allCars[1].y - (ourCar.speed + ourCar.y));
            } else if (allCars[1].speed > ourCar.speed) {
                // Hold position.
                costToCatchUp = monaco.getAccelerateCost(allCars[1].speed - ourCar.speed);
            }
        }

        // If we're in second place (index 1) + we can afford a shell:
        uint256 nextCarSpeed = allCars[0].speed;
        if (
            ourCarIndex == 1 &&
            nextCarSpeed > 3 &&
            ourCar.balance >= shellCost
        ) {
            // if the car ahead of us is going fast and it's not really expensive to get em, smoke em.
            if (shellCost < 300 && (
                nextCarSpeed > (ourCar.speed + 6) ||
                nextCarSpeed > 24)
            ) {
                ourCar.balance -= uint24(monaco.buyShell(1));
            } else if (
                shellCost < 1000 &&
                (nextCarSpeed > 35 || allCars[0].y - ourCar.y > 50 || allCars[0].y > 950 || ourCar.balance > 1000)
            ) {
                // The above thresholds for when to shell can be tuned; the ones above
                // are conservative to delay shelling until it's a desperate situation.
                ourCar.balance -= uint24(monaco.buyShell(1));
            }
        }

        if (
            // If we need to get moving, let's do it.
            ourCar.balance > (allCars[0].y < 800 ? 2000 : 500) &&
            ourCar.speed < 6
        ) {
            try monaco.buyAcceleration(ourCarIndex == 0 ? 2 : 4) returns (uint256 cost) {
                ourCar.balance -= uint24(cost);
                ourCar.speed += ourCarIndex == 0 ? 2 : 4;
            } catch {}
        } else if (
            // Keep pace early if in the back.
            costToCatchUp != 0 &&
            ourCar.balance > costToCatchUp &&
            costToCatchUp < 1000
        ) {
            uint256 catchUpAccelerationAmount = (allCars[1].speed - ourCar.speed) / (costToCatchUp < 50 ? 1 : 2);
            ourCar.balance -= uint24(monaco.buyAcceleration(catchUpAccelerationAmount));
            ourCar.speed += uint32(catchUpAccelerationAmount);
        } else {
            // Keep moving, faster near the end if balance permits
            uint256 accelerationTarget = (ourCar.y > 800) ? 5 : 2;

            uint256 costToAccelerate = monaco.getAccelerateCost(accelerationTarget);

            if (
                ourCar.balance > 200 &&
                ourCar.balance > costToAccelerate &&
                costToAccelerate < (ourCar.y > 800 ? 50 : 24)       
            ) {
                ourCar.balance -= uint24(monaco.buyAcceleration(accelerationTarget));
                ourCar.speed += uint32(accelerationTarget);
            }
        }

        // Go for a final boost when it makes sense
        if (ourCarIndex != 0 && allCars[0].y > 700 && ourCar.balance > allCars[0].balance * 2 && ourCar.balance > 220) {
            try monaco.buyAcceleration(5) {} catch {}
        }
    }

    function name() external pure returns (string memory) {
        return "c000r";
    }
}